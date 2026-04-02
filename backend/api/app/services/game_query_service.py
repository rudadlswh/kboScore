from __future__ import annotations

from datetime import date

from sqlalchemy.orm import Session

from app.repositories.event_repository import EventRepository
from app.repositories.game_repository import GameRepository
from app.repositories.snapshot_repository import SnapshotRepository
from app.repositories.weather_repository import WeatherRepository
from app.schemas.event import EventFeedItem, EventsFeedResponse, GameEventItem, GameEventsResponse, GameEventType
from app.schemas.game import (
    GameDetailResponse,
    GameListItem,
    GameSnapshotsResponse,
    GameSeasonClassification,
    GamesResponse,
    GameStatus,
    ScoreSummary,
    SnapshotResponse,
    StadiumSummary,
)
from app.schemas.team import TeamSummary
from app.schemas.weather import GameWeatherResponse, WeatherCurrent


class GameQueryService:
    """Read-side response shaping over the collector's canonical schema."""

    def __init__(
        self,
        *,
        game_repository: GameRepository,
        snapshot_repository: SnapshotRepository | None = None,
        weather_repository: WeatherRepository | None = None,
        event_repository: EventRepository | None = None,
    ) -> None:
        self.game_repository = game_repository
        self.snapshot_repository = snapshot_repository
        self.weather_repository = weather_repository
        self.event_repository = event_repository

    def list_games(
        self,
        db: Session,
        *,
        game_date: date,
        team_id: str | None,
        status: GameStatus | None,
    ) -> GamesResponse:
        rows = self.game_repository.list_games(
            db,
            game_date=game_date,
            team_id=team_id.strip().upper() if team_id else None,
            status=None,
        )
        items = [self._build_game_list_item(row) for row in rows]
        if status is not None:
            items = [item for item in items if item.status == status]
        return GamesResponse(
            date=game_date,
            games=items,
        )

    def get_game_detail(self, db: Session, game_id: str) -> GameDetailResponse | None:
        row = self.game_repository.get_game_detail_base(db, game_id)
        if row is None:
            return None

        assert self.weather_repository is not None
        weather_row = self.weather_repository.get_latest_weather_for_stadium(db, row["stadium_id"])
        status, score, inning_state = self._resolve_display_state(row)
        return GameDetailResponse(
            game_id=row["game_id"],
            provider_game_id=row["provider_game_id"],
            official_provider_game_id=row["official_provider_game_id"],
            scheduled_at=row["scheduled_at"],
            home_team=self._build_team_summary(row["home_team_id"], row["home_team_name_ko"]),
            away_team=self._build_team_summary(row["away_team_id"], row["away_team_name_ko"]),
            stadium=self._build_stadium_summary(row["stadium_id"], row["stadium_name_ko"]),
            status=status,
            season_classification=self._normalize_season_classification(row.get("season_classification")),
            score=score,
            inning_state=inning_state,
            latest_snapshot_at=row["latest_snapshot_at"],
            weather=self._build_weather_current(weather_row),
        )

    def get_game_snapshots(self, db: Session, game_id: str, *, limit: int) -> GameSnapshotsResponse | None:
        game_row = self.game_repository.get_game_lookup(db, game_id)
        if game_row is None:
            return None

        assert self.snapshot_repository is not None
        rows = self.snapshot_repository.list_game_snapshots(db, game_id, limit=limit)
        return GameSnapshotsResponse(
            game_id=game_row["game_id"],
            snapshots=[
                SnapshotResponse(
                    snapshot_at=row["snapshot_at"],
                    status=self._normalize_status(row["status"]),
                    score=self._build_score(row["home_score"], row["away_score"]),
                    inning_state=row["inning_state"],
                )
                for row in rows
            ],
        )

    def get_game_weather(self, db: Session, game_id: str) -> GameWeatherResponse | None:
        game_row = self.game_repository.get_game_lookup(db, game_id)
        if game_row is None:
            return None

        assert self.weather_repository is not None
        weather_row = self.weather_repository.get_latest_weather_for_stadium(db, game_row["stadium_id"])
        return GameWeatherResponse(
            game_id=game_row["game_id"],
            stadium_id=game_row["stadium_id"],
            current=self._build_weather_current(weather_row),
        )

    def list_team_games(
        self,
        db: Session,
        *,
        team_id: str,
        date_from: date,
        date_to: date,
        status: GameStatus | None,
    ) -> list[dict]:
        rows = self.game_repository.list_team_games(
            db,
            team_id=team_id.strip().upper(),
            date_from=date_from,
            date_to=date_to,
            status=None,
        )
        projected_rows = [self._project_team_game_row(row) for row in rows]
        if status is not None:
            return [
                row
                for row in projected_rows
                if self._normalize_status(row["status"], row.get("is_postponed"), row.get("is_cancelled")) == status
            ]
        return projected_rows

    def get_game_events(self, db: Session, game_id: str) -> GameEventsResponse | None:
        game_row = self.game_repository.get_game_lookup(db, game_id)
        if game_row is None:
            return None

        assert self.event_repository is not None
        rows = self.event_repository.list_game_events(db, game_id)
        return GameEventsResponse(
            game_id=game_row["game_id"],
            events=[
                GameEventItem(
                    event_type=GameEventType(row["event_type"]),
                    confirmed=bool(row["confirmed"]),
                    reason=row["reason"],
                    recorded_at=row["recorded_at"],
                )
                for row in rows
            ],
        )

    def list_events(
        self,
        db: Session,
        *,
        event_date: date,
        team_id: str | None,
        event_type: GameEventType | None,
    ) -> EventsFeedResponse:
        assert self.event_repository is not None
        rows = self.event_repository.list_events(
            db,
            event_date=event_date,
            team_id=team_id.strip().upper() if team_id else None,
            event_type=event_type.value if event_type else None,
        )
        return EventsFeedResponse(
            date=event_date,
            events=[
                EventFeedItem(
                    game_id=row["game_id"],
                    event_type=GameEventType(row["event_type"]),
                    confirmed=bool(row["confirmed"]),
                    reason=row["reason"],
                    recorded_at=row["recorded_at"],
                )
                for row in rows
            ],
        )

    def _build_game_list_item(self, row: dict) -> GameListItem:
        status, score, inning_state = self._resolve_display_state(row)
        return GameListItem(
            game_id=row["game_id"],
            scheduled_at=row["scheduled_at"],
            home_team=self._build_team_summary(row["home_team_id"], row["home_team_name_ko"]),
            away_team=self._build_team_summary(row["away_team_id"], row["away_team_name_ko"]),
            stadium=self._build_stadium_summary(row["stadium_id"], row["stadium_name_ko"]),
            status=status,
            season_classification=self._normalize_season_classification(row.get("season_classification")),
            score=score,
            inning_state=inning_state,
            # The current schema has no doubleheader flag, so the API exposes
            # a conservative false placeholder until the collector persists it.
            is_double_header=bool(row["is_double_header"]),
            is_postponed=bool(row["is_postponed"]),
        )

    @staticmethod
    def _build_team_summary(team_id: str, name_ko: str) -> TeamSummary:
        return TeamSummary(team_id=team_id, name_ko=name_ko)

    @staticmethod
    def _build_stadium_summary(stadium_id: str | None, stadium_name_ko: str | None) -> StadiumSummary:
        return StadiumSummary(stadium_id=stadium_id, name_ko=stadium_name_ko)

    @staticmethod
    def _build_score(home_score: int | None, away_score: int | None) -> ScoreSummary:
        return ScoreSummary(home=home_score, away=away_score)

    @staticmethod
    def _build_weather_current(row: dict | None) -> WeatherCurrent | None:
        if row is None:
            return None
        return WeatherCurrent(
            temperature_c=float(row["temperature_c"]) if row["temperature_c"] is not None else None,
            condition=row["condition"],
            precipitation_mm=float(row["precipitation_mm"]) if row["precipitation_mm"] is not None else None,
            observed_at=row["observed_at"],
        )

    def _resolve_display_state(self, row: dict) -> tuple[GameStatus, ScoreSummary, str | None]:
        canonical_status = self._normalize_status(row["status"], row.get("is_postponed"), row.get("is_cancelled"))
        snapshot_status = self._normalize_status(row.get("latest_snapshot_status"))
        if self._should_promote_live_from_snapshot(canonical_status, snapshot_status):
            return (
                GameStatus.LIVE,
                self._build_score(row.get("latest_snapshot_home_score"), row.get("latest_snapshot_away_score")),
                row.get("latest_snapshot_inning_state") or row.get("inning_state"),
            )
        return canonical_status, self._build_score(row.get("home_score"), row.get("away_score")), row.get("inning_state")

    @staticmethod
    def _should_promote_live_from_snapshot(canonical_status: GameStatus, snapshot_status: GameStatus) -> bool:
        if snapshot_status != GameStatus.LIVE:
            return False
        if canonical_status in {GameStatus.CANCELLED, GameStatus.POSTPONED, GameStatus.FINISHED}:
            return False
        return True

    @staticmethod
    def _normalize_season_classification(raw_value: str | None) -> GameSeasonClassification:
        if not raw_value:
            return GameSeasonClassification.UNKNOWN
        normalized = raw_value.strip().lower()
        if normalized in {classification.value for classification in GameSeasonClassification}:
            return GameSeasonClassification(normalized)
        return GameSeasonClassification.UNKNOWN

    def _project_team_game_row(self, row: dict) -> dict:
        canonical_status = self._normalize_status(row["status"], row.get("is_postponed"), row.get("is_cancelled"))
        snapshot_status = self._normalize_status(row.get("latest_snapshot_status"))
        if not self._should_promote_live_from_snapshot(canonical_status, snapshot_status):
            return dict(row)

        is_home = bool(row["is_home"])
        home_score = row.get("latest_snapshot_home_score")
        away_score = row.get("latest_snapshot_away_score")
        return {
            **dict(row),
            "status": GameStatus.LIVE.value,
            "inning_state": row.get("latest_snapshot_inning_state") or row.get("inning_state"),
            "my_team_score": home_score if is_home else away_score,
            "opponent_score": away_score if is_home else home_score,
        }

    @staticmethod
    def _normalize_status(
        raw_status: str | None,
        is_postponed: bool | None = None,
        is_cancelled: bool | None = None,
    ) -> GameStatus:
        if is_cancelled:
            return GameStatus.CANCELLED
        if is_postponed:
            return GameStatus.POSTPONED
        if not raw_status:
            return GameStatus.UNKNOWN
        normalized = raw_status.strip().lower()
        if normalized in {status.value for status in GameStatus}:
            return GameStatus(normalized)
        return GameStatus.UNKNOWN
