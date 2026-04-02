from __future__ import annotations

from dataclasses import dataclass

from app.schemas.game import GameSeasonClassification


REGULAR_SEASON_GAME_TARGET = 144


@dataclass(frozen=True, slots=True)
class TeamRegularSeasonRecord:
    team_id: str
    wins: int
    losses: int
    ties: int
    games_played: int
    remaining_regular_season_games: int
    unknown_classification_games: int

    @property
    def win_percentage(self) -> float | None:
        decisions = self.wins + self.losses
        if decisions <= 0:
            return None
        return self.wins / decisions


@dataclass(frozen=True, slots=True)
class RegularSeasonRecordSummary:
    records: list[TeamRegularSeasonRecord]
    has_unknown_classification_games: bool


class RegularSeasonRecordService:
    """
    Derives regular-season standings inputs from canonical game rows.

    This intentionally stops at standings inputs and remaining-games counts.
    It does not attempt KBO postseason probability or full tie-break logic.
    """

    def build_records(self, *, team_ids: list[str], games: list[dict]) -> RegularSeasonRecordSummary:
        wins = {team_id: 0 for team_id in team_ids}
        losses = {team_id: 0 for team_id in team_ids}
        ties = {team_id: 0 for team_id in team_ids}
        unknowns = {team_id: 0 for team_id in team_ids}

        for game in games:
            home_team_id = game.get("home_team_id")
            away_team_id = game.get("away_team_id")
            if home_team_id not in wins or away_team_id not in wins:
                continue

            season_classification = self._normalize_season_classification(game.get("season_classification"))
            if season_classification == GameSeasonClassification.UNKNOWN:
                unknowns[home_team_id] += 1
                unknowns[away_team_id] += 1
                continue
            if season_classification != GameSeasonClassification.REGULAR_SEASON:
                continue

            if game.get("status") != "finished":
                continue
            home_score = game.get("home_score")
            away_score = game.get("away_score")
            if home_score is None or away_score is None:
                continue

            if home_score == away_score:
                ties[home_team_id] += 1
                ties[away_team_id] += 1
            elif home_score > away_score:
                wins[home_team_id] += 1
                losses[away_team_id] += 1
            else:
                wins[away_team_id] += 1
                losses[home_team_id] += 1

        records = [
            self._build_record(
                team_id=team_id,
                wins=wins[team_id],
                losses=losses[team_id],
                ties=ties[team_id],
                unknown_classification_games=unknowns[team_id],
            )
            for team_id in team_ids
        ]
        records.sort(key=self._record_sort_key)
        return RegularSeasonRecordSummary(
            records=records,
            has_unknown_classification_games=any(record.unknown_classification_games > 0 for record in records),
        )

    @staticmethod
    def _build_record(
        *,
        team_id: str,
        wins: int,
        losses: int,
        ties: int,
        unknown_classification_games: int,
    ) -> TeamRegularSeasonRecord:
        games_played = wins + losses + ties
        return TeamRegularSeasonRecord(
            team_id=team_id,
            wins=wins,
            losses=losses,
            ties=ties,
            games_played=games_played,
            remaining_regular_season_games=max(0, REGULAR_SEASON_GAME_TARGET - games_played),
            unknown_classification_games=unknown_classification_games,
        )

    @staticmethod
    def _record_sort_key(record: TeamRegularSeasonRecord) -> tuple[float, int, int, int, str]:
        win_percentage = record.win_percentage if record.win_percentage is not None else -1.0
        return (
            -win_percentage,
            -record.wins,
            record.losses,
            -record.ties,
            record.team_id,
        )

    @staticmethod
    def _normalize_season_classification(raw_value: str | None) -> GameSeasonClassification:
        if not raw_value:
            return GameSeasonClassification.UNKNOWN
        normalized = raw_value.strip().lower()
        if normalized in {classification.value for classification in GameSeasonClassification}:
            return GameSeasonClassification(normalized)
        return GameSeasonClassification.UNKNOWN
