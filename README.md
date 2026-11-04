# Better HUD

A mod for HELLDIVERS (2015) that adds to the game's HUD, for [Obsidian Mod Manager](https://github.com/Alomare/ObsidianModManager). Each part can be turned on or off in the pause menu, under **Mods → Better HUD**.

- **Ammo counter** (on): over the magazine count, the rounds left in the magazine, for guns, flamethrowers and launchers. Lasers and arc weapons, which heat or charge up instead, get no counter. The counter hides while a stratagem code is entered or a stratagem beacon is held.
- **Player health bars** (on): a red bar under each player card, in missions. White chunks fade out where health was lost, as on the game's bars. A cyan bar over the top half shows the shield, from the Shield Generator Pack or the shield upgrade in Helldivers Arcade. While a player is downed, the bar turns crimson as they bleed out, with a yellow bar under it showing how close they are to getting back up.
- **Health numbers** (off): current and maximum health at the left of each player health bar.
- **Enemy health bars** (on): a bar over every enemy the player hits, and every heavy any player hurts. Bug bars are orange, cyborg bars red and Illuminate bars purple. White chunks fade out where health was lost, a pulsing outline shows a burn (orange), poison (green) or stun (blue), bigger enemies get bigger bars, and a bar flashes white when the enemy dies. Bars follow the UI scale setting.
- **Reload circle** (on): a light grey ring to the right of each local Helldiver that fills while the weapon in hand reloads, on a see-through dark track. A finished reload makes the ring grow and fade out in a tenth of a second. The ring follows the UI scale setting.
- **Hide on-player health bar** and **Hide on-player recovery bar** (off): hide the bars the game draws over each Helldiver.
- **Damage numbers** (both): numbers in the HUD's own font, with a faint dark outline, that rise and fade where damage lands, on enemies the player hits, on players losing health, or both. Off shows none. **Damage numbers mode** (accumulated) picks one number per hit (stacked) or one per burst of hits on a target (accumulated). **Damage numbers position** (next to the entity) can also put them above the health bar or where each hit landed.

Needs Obsidian API 1.11.0 or later for the Mods page, and 1.14.0 or later for damage numbers on enemies and for enemy bars that follow the player's hits. With an older one, every part keeps its default, and every damaged enemy gets a bar.
