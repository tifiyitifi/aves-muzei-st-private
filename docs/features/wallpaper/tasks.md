# Wallpaper family — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| Host test for the refill entrypoint's channel contract | `REF-1`..`REF-5` are device-only today; the handler/target dispatch could be driven with a fake channel | `REF-1`, `REF-3` |
| Host test for the grouped auto-advance visibility gate | the deferral is only exercised on a device, and it is the rule that keeps video playback from baking | `AUT-9` |
| A Dart test for the interval fan-out to both walls | the controller rules cover the catalog; the reset seam is covered in the grouped controller test only | `AUT-5` |
| Decide whether the Muzei wallpaper should honour the same visibility deferral as the grouped one | today only the grouped worker defers; the difference is deliberate but not documented in one place | `AUT-9` (design) |

Not planned: a real security boundary for the locks. They are casual protection
inside Aves (`0003`), and the vault remains the privacy feature.
