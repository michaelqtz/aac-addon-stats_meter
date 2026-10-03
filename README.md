# Stats Meter

A damage and healing meter for ArcheAge Classic. Stats Meter tracks damage, DPS, healing, HPS, damage taken and damage absorbed for you, your group and everyone around you.

## Installation

1. Download the latest release.
2. Extract it into your ArcheAge Classic `Addon` folder. The folder must be named `stats_meter`, so the files end up at `Addon/stats_meter/main.lua`.
3. Enable **stats_meter** in your addon settings and log in.

When it loads you'll see `[Stats Meter] Successfully loaded` in chat.

## Using the meter

- **Change what's shown:** click the title (e.g. "Total Damage") to pick a stat:
  - Total Damage
  - Damage Per Second
  - Total Healing
  - Healing Per Second
  - Damage Taken
  - Damage Absorbed (%)
- **Scroll:** use the mouse wheel over the meter to see everyone beyond the top 12. The numbers on the left show each unit's rank.
- **Always see yourself:** if you're scrolled out of view or ranked below the visible rows, you're pinned to the bottom row with your real rank.
- **Move it:** hold **Shift** and drag the title bar.
- **See a skill breakdown:** click anyone's row to open a window listing their skills by amount and percentage.
- **Reset:** click the reset button next to the timer. The current fight is saved to a log file first (see [Logs](#logs)).
- **Minimize:** click the button in the top-right corner. Click it again on the small bar to bring the meter back.

The timer starts with the first combat event, so idle time before a fight doesn't lower DPS and HPS.

### Bar colours

| Colour | Who |
|---|---|
| Turquoise | You |
| Blue | Your party or raid members |
| Green | Other players |
| Red | Hostile players and NPCs |
| Orange | Friendly NPCs |

## Settings

Press **ESC** and click **Stats Meter** under **Addon Options** on the left side of the menu.

The **Filters** dropdown toggles which units are shown. Green means the filter is on and red means it's off.

| Filter | Default | Shows |
|---|---|---|
| Players | On | Player characters |
| Hostiles | On | Hostile players and units |
| NPCs | Off | Non-player characters, pets and other units |

The meter remembers its position, selected stat, filters and minimized state between sessions.

## Dungeons

When you enter a dungeon, the meter asks whether you want to reset it, so each run starts fresh. Choosing **Yes** saves a log of the previous fight before resetting.

## Logs

Every reset of a meter with data saves it to `Addon/stats_meter/logs/`, with the start and end time in the file name. These files are only for your own records. You can delete them at any time.

## Notes

- The meter counts every combat message your client receives, so it includes anyone fighting within range, not just your group.
- Percentages are out of the units currently shown, so they always add up to 100%. Changing a filter never loses data; hidden units are still recorded.
- "Reset After Duel" (the full heal at the end of a duel) isn't counted as healing.
- The addon API only lets the meter identify you, your party or raid members, and your current target. Anyone else (such as nearby players outside your group, or NPCs) isn't shown.

## Changelog

### 2.2.0
- The meter now scrolls with the mouse wheel, and you're always pinned to the bottom row when you'd otherwise be out of view.
- Other players now appear on the meter. Before, only your own character showed up for most people.
- Duels no longer break the meter, and "Reset After Duel" no longer counts as healing.
- Fixed the Damage Absorbed percentage, which was miscalculated.
- An unexpected combat event can no longer freeze the meter's display.
- Melee hits now appear in the skill breakdown as "Melee Attack".
- Settings are saved as soon as you change them, including whether the meter is minimized.
- Fixed slowdowns in long sessions and leftover windows after reloading addons.
