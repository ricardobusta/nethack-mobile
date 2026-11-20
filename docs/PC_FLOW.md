# NetHack 5.0.0 PC flow comparison

Reference: the pristine vendored `NetHack-5.0.0_Released` terminal port, built
locally with ncurses on macOS. The comparison used real terminal screens, not
screenshots of an older release. The raw session is retained in the validation
bundle as `pc-flow.log`. The reference used `OPTIONS=!news` and otherwise normal
new-game defaults. Official background: [5.0 Guidebook](https://www.nethack.org/v500/Guidebook.html).

| Decision | PC reference | Mobile presentation |
| --- | --- | --- |
| Character selection | Randomize query, role, race, gender, alignment; alternate choice order and filters; final confirmation | Same upstream `genl_player_setup` menus, rendered as touch rows. Character name is entered first. |
| Introduction | Deity/role-specific Book introduction, then welcome | Same upstream text window and Continue. Removed both mobile overrides that disabled `legacy`. |
| Tutorial | Yes/no menu after welcome; explicit option to skip | Same engine menu. Tests choose “No, just start play”; the Yes path remains available. |
| Status | Two terminal status lines, separate from the top message line | Read-only HP/Power bars and condition badges. Avatar opens class/rank, race, gender, alignment, attributes and equipment; Inventory also has a shortcut. |
| Inventory | Lettered known item names, stacks and equipped annotations | Engine names, appearance tiles, quantities and equipped annotations, with Character/Inventory tabs. |
| Item actions | Selecting the bullwhip opens “Do what with the bullwhip?”; wield, apply, name, drop, engrave, adjust, quiver, throw, swap, two-weapon and encyclopedia choices | The same `itemactions` menu in Item details. Actions, eligibility and pushed commands remain upstream-owned. Back cancels it and reopens Inventory without advancing time. |
| Numeric answers | `#`/digits set `yn_number`; zero answers No | Numeric widget submits a full decimal long, with zero/positive/overflow handling. Canceling numeric entry reopens the original question; Escape/default and letter-case handling match the PC prompt. Quantity and multiselect menus retain index/count responses. |
| Targeting | Farlook tip, cursor directions and selection; Escape cancels; no time passes while browsing | Same requests, with map taps, direction pad and Keys available. |
| Save/restore | “Really save?”, save exit; restoring prints a greeting | Explicit Save follows engine prompts. Background suspension uses its hangup/save boundary; living games resume immediately and silently. |
| End disclosures | Possessions identification, attributes, conduct, overview, other eligible disclosures, then final outcome/score | Each upstream choice and text page is retained. Backgrounding leaves the request and UI untouched. A separate read-only Last run journal survives process termination. |

The reference session exercised character confirmation, introduction, tutorial
choice, inventory and item actions, farlook, explicit save, restore, quit and
postmortem disclosures. Actual death and its background behavior are additionally
covered by the native and Godot regressions. Quit and death share the upstream
irreversible `really_done` boundary; the copied outcome distinguishes them.

The frontend does not synthesize missing disclosure pages or expose information
the player declined to view. Item payloads contain the same `doname` text the
engine rendered, stack count, equipped state and appearance tile. They contain
no object type, enchantment, blessing, hidden resistances or discovery flags.
Information already known to the character may appear in the upstream name.
