from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
import hashlib
import math
import random

from app.schemas.game import GameSeasonClassification
from app.services.regular_season_ranking_service import (
    RankedTeamRegularSeasonRecord,
    RegularSeasonRankingService,
    RankingResolution,
)
from app.services.regular_season_record_service import (
    REGULAR_SEASON_GAME_TARGET,
    RegularSeasonRecordService,
    TeamRegularSeasonRecord,
)


class PostseasonProbabilityUnavailableReason(StrEnum):
    UNKNOWN_CLASSIFICATION_GAMES = "unknown_classification_games"
    INCOMPLETE_REGULAR_SEASON_SCHEDULE = "incomplete_regular_season_schedule"
    INSUFFICIENT_COMPLETED_REGULAR_SEASON_GAMES = "insufficient_completed_regular_season_games"


@dataclass(frozen=True, slots=True)
class TeamPostseasonQualificationProbability:
    team_id: str
    probability: float | None
    unavailable_reason: PostseasonProbabilityUnavailableReason | None = None


@dataclass(frozen=True, slots=True)
class PostseasonQualificationProbabilitySummary:
    probabilities_by_team_id: dict[str, TeamPostseasonQualificationProbability]
    simulation_count: int


@dataclass(frozen=True, slots=True)
class _TeamRunProfile:
    offense_runs_per_game: float
    defense_runs_per_game: float


class PostseasonQualificationProbabilityService:
    """
    Schedule-aware Monte Carlo model for regular-season top-5 qualification.

    Required inputs:
    - regular-season finished games for current wins/losses/ties and scoring rates
    - complete remaining regular-season schedule
    - KBO-aware ranking service for end-of-season ordering

    Availability rules:
    - any unknown-classification season game blocks probabilities
    - incomplete remaining regular-season schedule coverage blocks probabilities
    - zero completed regular-season games blocks probabilities
    """

    DEFAULT_SIMULATION_COUNT = 5_000
    SHRINKAGE_GAMES = 12

    def __init__(
        self,
        *,
        record_service: RegularSeasonRecordService,
        ranking_service: RegularSeasonRankingService,
        simulation_count: int = DEFAULT_SIMULATION_COUNT,
    ) -> None:
        self.record_service = record_service
        self.ranking_service = ranking_service
        self.simulation_count = simulation_count

    def calculate_probabilities(
        self,
        *,
        team_ids: list[str],
        games: list[dict],
        previous_regular_season_rank_by_team_id: dict[str, int | None],
    ) -> PostseasonQualificationProbabilitySummary:
        if self._contains_unknown_classification_games(games):
            return self._unavailable_summary(
                team_ids=team_ids,
                reason=PostseasonProbabilityUnavailableReason.UNKNOWN_CLASSIFICATION_GAMES,
            )

        finished_regular_season_games = self._finished_regular_season_games(games)
        if not finished_regular_season_games:
            return self._unavailable_summary(
                team_ids=team_ids,
                reason=PostseasonProbabilityUnavailableReason.INSUFFICIENT_COMPLETED_REGULAR_SEASON_GAMES,
            )

        record_summary = self.record_service.build_records(team_ids=team_ids, games=games)
        remaining_schedule_games = self._remaining_regular_season_games(games)
        if not self._has_complete_schedule_coverage(
            records=record_summary.records,
            remaining_schedule_games=remaining_schedule_games,
        ):
            return self._unavailable_summary(
                team_ids=team_ids,
                reason=PostseasonProbabilityUnavailableReason.INCOMPLETE_REGULAR_SEASON_SCHEDULE,
            )

        run_profiles = self._build_run_profiles(team_ids=team_ids, games=finished_regular_season_games)
        simulation_seed = self._simulation_seed(games)
        random_generator = random.Random(simulation_seed)
        qualification_counts = {team_id: 0 for team_id in team_ids}
        base_games = [self._make_simulated_game(game) for game in finished_regular_season_games]
        base_records_by_team_id = {record.team_id: record for record in record_summary.records}

        for _ in range(self.simulation_count):
            wins = {team_id: base_records_by_team_id[team_id].wins for team_id in team_ids}
            losses = {team_id: base_records_by_team_id[team_id].losses for team_id in team_ids}
            ties = {team_id: base_records_by_team_id[team_id].ties for team_id in team_ids}
            simulated_games = list(base_games)

            for game in remaining_schedule_games:
                simulated_game = self._simulate_regular_season_game(
                    game=game,
                    run_profiles=run_profiles,
                    random_generator=random_generator,
                )
                simulated_games.append(simulated_game)
                self._apply_result(
                    simulated_game=simulated_game,
                    wins=wins,
                    losses=losses,
                    ties=ties,
                )

            simulated_records = [
                TeamRegularSeasonRecord(
                    team_id=team_id,
                    wins=wins[team_id],
                    losses=losses[team_id],
                    ties=ties[team_id],
                    games_played=wins[team_id] + losses[team_id] + ties[team_id],
                    remaining_regular_season_games=max(
                        0,
                        REGULAR_SEASON_GAME_TARGET - (wins[team_id] + losses[team_id] + ties[team_id]),
                    ),
                    unknown_classification_games=0,
                )
                for team_id in team_ids
            ]
            ranked_records = self.ranking_service.rank_records(
                records=simulated_records,
                games=simulated_games,
                previous_regular_season_rank_by_team_id=previous_regular_season_rank_by_team_id,
            )
            qualified_team_ids = self._determine_qualified_team_ids(
                ranked_records=ranked_records,
                run_profiles=run_profiles,
                random_generator=random_generator,
            )
            for team_id in qualified_team_ids:
                qualification_counts[team_id] += 1

        return PostseasonQualificationProbabilitySummary(
            probabilities_by_team_id={
                team_id: TeamPostseasonQualificationProbability(
                    team_id=team_id,
                    probability=qualification_counts[team_id] / self.simulation_count,
                )
                for team_id in team_ids
            },
            simulation_count=self.simulation_count,
        )

    @staticmethod
    def _contains_unknown_classification_games(games: list[dict]) -> bool:
        for game in games:
            if game.get("season_classification") == GameSeasonClassification.UNKNOWN.value:
                return True
        return False

    @staticmethod
    def _finished_regular_season_games(games: list[dict]) -> list[dict]:
        return [
            game
            for game in games
            if game.get("season_classification") == GameSeasonClassification.REGULAR_SEASON.value
            and game.get("status") == "finished"
            and game.get("home_score") is not None
            and game.get("away_score") is not None
        ]

    @staticmethod
    def _remaining_regular_season_games(games: list[dict]) -> list[dict]:
        remaining_games = [
            game
            for game in games
            if game.get("season_classification") == GameSeasonClassification.REGULAR_SEASON.value
            and game.get("status") != "finished"
            and not bool(game.get("is_cancelled"))
        ]
        return sorted(
            remaining_games,
            key=lambda game: (
                game.get("scheduled_at").isoformat() if game.get("scheduled_at") else "",
                game.get("game_id") or "",
            ),
        )

    @staticmethod
    def _has_complete_schedule_coverage(
        *,
        records: list[TeamRegularSeasonRecord],
        remaining_schedule_games: list[dict],
    ) -> bool:
        remaining_count_by_team_id = {record.team_id: 0 for record in records}
        for game in remaining_schedule_games:
            home_team_id = game.get("home_team_id")
            away_team_id = game.get("away_team_id")
            if home_team_id in remaining_count_by_team_id:
                remaining_count_by_team_id[home_team_id] += 1
            if away_team_id in remaining_count_by_team_id:
                remaining_count_by_team_id[away_team_id] += 1

        for record in records:
            if remaining_count_by_team_id[record.team_id] != record.remaining_regular_season_games:
                return False
        return True

    def _build_run_profiles(self, *, team_ids: list[str], games: list[dict]) -> dict[str, _TeamRunProfile]:
        runs_scored = {team_id: 0 for team_id in team_ids}
        runs_allowed = {team_id: 0 for team_id in team_ids}
        games_count = {team_id: 0 for team_id in team_ids}
        total_runs = 0

        for game in games:
            home_team_id = game["home_team_id"]
            away_team_id = game["away_team_id"]
            home_score = int(game["home_score"])
            away_score = int(game["away_score"])
            total_runs += home_score + away_score

            if home_team_id in runs_scored:
                runs_scored[home_team_id] += home_score
                runs_allowed[home_team_id] += away_score
                games_count[home_team_id] += 1
            if away_team_id in runs_scored:
                runs_scored[away_team_id] += away_score
                runs_allowed[away_team_id] += home_score
                games_count[away_team_id] += 1

        league_average_runs = total_runs / (2 * len(games))
        return {
            team_id: _TeamRunProfile(
                offense_runs_per_game=(runs_scored[team_id] + (self.SHRINKAGE_GAMES * league_average_runs))
                / (games_count[team_id] + self.SHRINKAGE_GAMES),
                defense_runs_per_game=(runs_allowed[team_id] + (self.SHRINKAGE_GAMES * league_average_runs))
                / (games_count[team_id] + self.SHRINKAGE_GAMES),
            )
            for team_id in team_ids
        }

    def _simulate_regular_season_game(
        self,
        *,
        game: dict,
        run_profiles: dict[str, _TeamRunProfile],
        random_generator: random.Random,
    ) -> dict:
        home_team_id = game["home_team_id"]
        away_team_id = game["away_team_id"]
        home_lambda, away_lambda = self._expected_runs(
            home_team_id=home_team_id,
            away_team_id=away_team_id,
            run_profiles=run_profiles,
        )
        home_score = self._sample_poisson(home_lambda, random_generator)
        away_score = self._sample_poisson(away_lambda, random_generator)

        return {
            "game_id": game.get("game_id"),
            "home_team_id": home_team_id,
            "away_team_id": away_team_id,
            "season_classification": GameSeasonClassification.REGULAR_SEASON.value,
            "status": "finished",
            "home_score": home_score,
            "away_score": away_score,
        }

    def _determine_qualified_team_ids(
        self,
        *,
        ranked_records: list[RankedTeamRegularSeasonRecord],
        run_profiles: dict[str, _TeamRunProfile],
        random_generator: random.Random,
    ) -> set[str]:
        tiebreak_teams = [
            record
            for record in ranked_records
            if record.ranking_resolution == RankingResolution.TIEBREAK_GAME_REQUIRED
            and record.ranking_resolution_position == 5
        ]
        if len(tiebreak_teams) == 2:
            qualified_team_ids = {record.team_id for record in ranked_records if record.rank < 5}
            winner_team_id = self._simulate_rank_five_tiebreak(
                first_team_id=tiebreak_teams[0].team_id,
                second_team_id=tiebreak_teams[1].team_id,
                run_profiles=run_profiles,
                random_generator=random_generator,
            )
            qualified_team_ids.add(winner_team_id)
            return qualified_team_ids

        return {record.team_id for record in ranked_records if record.rank <= 5}

    def _simulate_rank_five_tiebreak(
        self,
        *,
        first_team_id: str,
        second_team_id: str,
        run_profiles: dict[str, _TeamRunProfile],
        random_generator: random.Random,
    ) -> str:
        while True:
            home_lambda, away_lambda = self._expected_runs(
                home_team_id=first_team_id,
                away_team_id=second_team_id,
                run_profiles=run_profiles,
            )
            first_score = self._sample_poisson(home_lambda, random_generator)
            second_score = self._sample_poisson(away_lambda, random_generator)
            if first_score == second_score:
                continue
            return first_team_id if first_score > second_score else second_team_id

    @staticmethod
    def _apply_result(
        *,
        simulated_game: dict,
        wins: dict[str, int],
        losses: dict[str, int],
        ties: dict[str, int],
    ) -> None:
        home_team_id = simulated_game["home_team_id"]
        away_team_id = simulated_game["away_team_id"]
        home_score = simulated_game["home_score"]
        away_score = simulated_game["away_score"]
        if home_score == away_score:
            ties[home_team_id] += 1
            ties[away_team_id] += 1
            return
        if home_score > away_score:
            wins[home_team_id] += 1
            losses[away_team_id] += 1
            return
        wins[away_team_id] += 1
        losses[home_team_id] += 1

    @staticmethod
    def _make_simulated_game(game: dict) -> dict:
        return {
            "game_id": game.get("game_id"),
            "home_team_id": game["home_team_id"],
            "away_team_id": game["away_team_id"],
            "season_classification": GameSeasonClassification.REGULAR_SEASON.value,
            "status": "finished",
            "home_score": int(game["home_score"]),
            "away_score": int(game["away_score"]),
        }

    @staticmethod
    def _expected_runs(
        *,
        home_team_id: str,
        away_team_id: str,
        run_profiles: dict[str, _TeamRunProfile],
    ) -> tuple[float, float]:
        home_profile = run_profiles[home_team_id]
        away_profile = run_profiles[away_team_id]
        league_average_runs = (
            home_profile.offense_runs_per_game
            + home_profile.defense_runs_per_game
            + away_profile.offense_runs_per_game
            + away_profile.defense_runs_per_game
        ) / 4
        league_average_runs = max(0.25, league_average_runs)
        home_lambda = max(
            0.25,
            home_profile.offense_runs_per_game * (away_profile.defense_runs_per_game / league_average_runs),
        )
        away_lambda = max(
            0.25,
            away_profile.offense_runs_per_game * (home_profile.defense_runs_per_game / league_average_runs),
        )
        return home_lambda, away_lambda

    @staticmethod
    def _sample_poisson(lmbda: float, random_generator: random.Random) -> int:
        threshold = math.exp(-lmbda)
        product = 1.0
        count = 0
        while product > threshold:
            count += 1
            product *= random_generator.random()
        return count - 1

    @staticmethod
    def _simulation_seed(games: list[dict]) -> int:
        fingerprint = "|".join(
            sorted(
                (
                    f"{game.get('game_id')}:{game.get('season_classification')}:{game.get('status')}:"
                    f"{game.get('home_team_id')}:{game.get('away_team_id')}:"
                    f"{game.get('home_score')}:{game.get('away_score')}"
                )
                for game in games
            )
        )
        digest = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()
        return int(digest[:16], 16)

    def _unavailable_summary(
        self,
        *,
        team_ids: list[str],
        reason: PostseasonProbabilityUnavailableReason,
    ) -> PostseasonQualificationProbabilitySummary:
        return PostseasonQualificationProbabilitySummary(
            probabilities_by_team_id={
                team_id: TeamPostseasonQualificationProbability(
                    team_id=team_id,
                    probability=None,
                    unavailable_reason=reason,
                )
                for team_id in team_ids
            },
            simulation_count=0,
        )
