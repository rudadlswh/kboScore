from __future__ import annotations

from collector.services.kbo_schedule_source import KBOScheduleSource, ScheduleSourceRequest


def test_non_march_schedule_scope_defaults_to_regular_season_when_row_has_no_explicit_label():
    classification = KBOScheduleSource._derive_season_classification(  # noqa: SLF001 - targeted regression coverage
        request=ScheduleSourceRequest(season_id=2026, month=4),
        play_html="<span>KT</span><span>vs</span><span>LG</span>",
        relay_text="프리뷰",
        note_text="",
    )

    assert classification.value == "regular_season"


def test_march_mixed_schedule_scope_keeps_unknown_without_explicit_label():
    classification = KBOScheduleSource._derive_season_classification(  # noqa: SLF001 - targeted regression coverage
        request=ScheduleSourceRequest(season_id=2026, month=3),
        play_html="<span>KT</span><span>vs</span><span>LG</span>",
        relay_text="프리뷰",
        note_text="",
    )

    assert classification.value == "unknown"
