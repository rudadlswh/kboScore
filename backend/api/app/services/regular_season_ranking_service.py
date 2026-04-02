from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from app.schemas.game import GameSeasonClassification
from app.services.regular_season_record_service import TeamRegularSeasonRecord


class RankingResolution(StrEnum):
    RESOLVED = "resolved"
    TIEBREAK_GAME_REQUIRED = "tiebreak_game_required"


@dataclass(frozen=True, slots=True)
class RankedTeamRegularSeasonRecord:
    team_id: str
    rank: int
    wins: int
    losses: int
    ties: int
    games_played: int
    remaining_regular_season_games: int
    unknown_classification_games: int
    win_percentage: float | None
    ranking_resolution: RankingResolution
    ranking_resolution_position: int | None


@dataclass(frozen=True, slots=True)
class _HeadToHeadMetrics:
    wins: int = 0
    runs_scored: int = 0


class RegularSeasonRankingService:
    TIEBREAK_GAME_TARGET_RANKS = {1, 5}

    def rank_records(
        self,
        *,
        records: list[TeamRegularSeasonRecord],
        games: list[dict],
        previous_regular_season_rank_by_team_id: dict[str, int | None],
    ) -> list[RankedTeamRegularSeasonRecord]:
        ordered_records = sorted(records, key=self._record_sort_key)
        head_to_head_metrics = self._build_head_to_head_metrics(games)

        ranked_records: list[RankedTeamRegularSeasonRecord] = []
        cursor = 0
        while cursor < len(ordered_records):
            current_group = [ordered_records[cursor]]
            while (
                cursor + len(current_group) < len(ordered_records)
                and self._has_same_win_percentage(
                    ordered_records[cursor + len(current_group)],
                    current_group[0],
                )
            ):
                current_group.append(ordered_records[cursor + len(current_group)])

            start_rank = len(ranked_records) + 1
            ranking_resolution = (
                RankingResolution.TIEBREAK_GAME_REQUIRED
                if len(current_group) == 2 and start_rank in self.TIEBREAK_GAME_TARGET_RANKS
                else RankingResolution.RESOLVED
            )
            ordered_group = self._resolve_tied_group(
                current_group,
                head_to_head_metrics=head_to_head_metrics,
                previous_regular_season_rank_by_team_id=previous_regular_season_rank_by_team_id,
            )
            ranked_records.extend(
                RankedTeamRegularSeasonRecord(
                    team_id=record.team_id,
                    rank=start_rank + index,
                    wins=record.wins,
                    losses=record.losses,
                    ties=record.ties,
                    games_played=record.games_played,
                    remaining_regular_season_games=record.remaining_regular_season_games,
                    unknown_classification_games=record.unknown_classification_games,
                    win_percentage=record.win_percentage,
                    ranking_resolution=ranking_resolution,
                    ranking_resolution_position=start_rank if ranking_resolution == RankingResolution.TIEBREAK_GAME_REQUIRED else None,
                )
                for index, record in enumerate(ordered_group)
            )
            cursor += len(current_group)

        return ranked_records

    @staticmethod
    def _record_sort_key(record: TeamRegularSeasonRecord) -> tuple[float, int, int, str]:
        win_percentage = record.win_percentage if record.win_percentage is not None else -1.0
        return (-win_percentage, -record.wins, record.losses, record.team_id)

    def _resolve_tied_group(
        self,
        records: list[TeamRegularSeasonRecord],
        *,
        head_to_head_metrics: dict[tuple[str, str], _HeadToHeadMetrics],
        previous_regular_season_rank_by_team_id: dict[str, int | None],
    ) -> list[TeamRegularSeasonRecord]:
        if len(records) <= 1:
            return records

        missing_previous_ranks = [
            record.team_id
            for record in records
            if previous_regular_season_rank_by_team_id.get(record.team_id) is None
        ]
        if missing_previous_ranks:
            missing_team_ids = ", ".join(sorted(missing_previous_ranks))
            raise ValueError(f"Missing previous_regular_season_rank for tied teams: {missing_team_ids}")

        team_ids = {record.team_id for record in records}
        group_metrics: dict[str, _HeadToHeadMetrics] = {}
        for team_id in team_ids:
            metrics = _HeadToHeadMetrics()
            for opponent_team_id in team_ids:
                if opponent_team_id == team_id:
                    continue
                matchup_metrics = head_to_head_metrics.get((team_id, opponent_team_id), _HeadToHeadMetrics())
                metrics = _HeadToHeadMetrics(
                    wins=metrics.wins + matchup_metrics.wins,
                    runs_scored=metrics.runs_scored + matchup_metrics.runs_scored,
                )
            group_metrics[team_id] = metrics

        return sorted(
            records,
            key=lambda record: (
                -group_metrics[record.team_id].wins,
                -group_metrics[record.team_id].runs_scored,
                previous_regular_season_rank_by_team_id[record.team_id],
                record.team_id,
            ),
        )

    @staticmethod
    def _build_head_to_head_metrics(games: list[dict]) -> dict[tuple[str, str], _HeadToHeadMetrics]:
        metrics: dict[tuple[str, str], _HeadToHeadMetrics] = {}
        for game in games:
            season_classification = game.get("season_classification")
            if season_classification != GameSeasonClassification.REGULAR_SEASON.value:
                continue
            if game.get("status") != "finished":
                continue

            home_team_id = game.get("home_team_id")
            away_team_id = game.get("away_team_id")
            home_score = game.get("home_score")
            away_score = game.get("away_score")
            if not home_team_id or not away_team_id or home_score is None or away_score is None:
                continue

            metrics[(home_team_id, away_team_id)] = _HeadToHeadMetrics(
                wins=metrics.get((home_team_id, away_team_id), _HeadToHeadMetrics()).wins + int(home_score > away_score),
                runs_scored=metrics.get((home_team_id, away_team_id), _HeadToHeadMetrics()).runs_scored + int(home_score),
            )
            metrics[(away_team_id, home_team_id)] = _HeadToHeadMetrics(
                wins=metrics.get((away_team_id, home_team_id), _HeadToHeadMetrics()).wins + int(away_score > home_score),
                runs_scored=metrics.get((away_team_id, home_team_id), _HeadToHeadMetrics()).runs_scored + int(away_score),
            )

        return metrics

    @staticmethod
    def _has_same_win_percentage(lhs: TeamRegularSeasonRecord, rhs: TeamRegularSeasonRecord) -> bool:
        lhs_decisions = lhs.wins + lhs.losses
        rhs_decisions = rhs.wins + rhs.losses
        if lhs_decisions == 0 or rhs_decisions == 0:
            return lhs_decisions == rhs_decisions
        return lhs.wins * rhs_decisions == rhs.wins * lhs_decisions
