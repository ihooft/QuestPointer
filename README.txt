QuestPointer 1.1.3 - WoW Forever (Interface 16001)

INSTALL
Extract QuestPointer into Interface/AddOns, replacing the existing folder.
The path should be Interface/AddOns/QuestPointer/QuestPointer.toc.
Restart the client for a first install; /reload after updating.

USE
Select a quest for navigation in the map or objective tracker. QuestPointer
follows the supertracked quest, falling back to the selected quest when no
supertracked quest ID exists. The arrow rotates relative to your character's
facing: up means ahead, right means turn right, down means behind.
Distance in yards and objective progress appear below it. Plain objectives
such as Report to Deputy Feldon display without an artificial counter.

OPTIONS
All controls are in the main Options window under AddOns > QuestPointer.
Type /qp or /questpointer, or choose Options from the arrow's right-click
menu, to open that page. There is no separate addon options dialog.

Choose 2D Simple or 3D, then use the Arrow color slider to select a hue. The 3D arrow uses 64
perspective-rendered headings: up points away from you; down points toward
you. It is a shaded arrow on a tilted plane, not an arrow that simply rotates
flat on the screen. The direction changes in approximately 5.6-degree steps.
2D Simple rotates continuously.

Arrow size ranges from 24 to 160 UI pixels. The same page contains Show arrow,
Lock arrow position, Reset size, and Reset position. Settings save per character.
Closing the Options window leaves the arrow visible. /qp close hides it;
/qp shows it again and opens the Options page.

Right-click menu: Options, Lock/Unlock Arrow, Reset Position, Close.
Left-click and drag to move the arrow while unlocked. Reset Position returns
it to the top center. Objective text moves and hides with the arrow.

NAVIGATION AND DIAGNOSTICS
Uses navigation waypoints first, then the matching quest's map objective
marker. This is a directional compass with straight-line distance to the
tracked marker, not terrain-aware routing. Missing coordinates show a dim
upward arrow and Distance unavailable. 
Run /qp debug to report quest IDs, map-marker lookup, positions and facing.
Numerical objective counters update while playing; quests without numerical
objectives use the quest's waypoint text or quest-log objective summary.

VALIDATION
Lua and simulated UI/navigation checks passed, including objective formatting,
main Options integration, graphic selection and 3D heading frames. Confirm
appearance and behavior in WoW Forever, since the client is not available here.

NEW IN 1.0.9
Hover tooltip removed. Transparency slider (0% opaque to 100% invisible)
affects the arrow and attached text. /qp still opens options when invisible.
Shared profiles are account-wide on the same WoW installation. Enter a name
and click Save / overwrite named profile; on another character, choose the
saved profile and click Load selected profile. Profiles include graphic,
size, color, transparency, visibility, lock state and position. Loading copies
the settings; later character changes do not change the saved profile.
Log out or reload the saving character before switching characters.

NEW IN 1.1.0
Options > AddOns > QuestPointer is the Appearance page. Expand QuestPointer
in the category list and select Profiles to save/load shared settings.
Profile selection uses a native dropdown with checked selection and scrolling.
Existing character settings and shared profiles are retained.

NEW IN 1.1.1
While dead or a ghost, the corpse takes priority over the quest. The distance
is to the corpse and the text reads Return to your corpse. Navigation resumes
the selected quest on resurrection. If alive with no supertracked or selected
quest, the arrow hides automatically, reappearing when a quest is selected.
Manual Close and Show arrow settings still apply. If the game supplies no
corpse coordinates, the arrow dims and reports unavailable distance.

NEW IN 1.1.2
Selecting a user waypoint or built-in map pin for navigation makes the arrow
follow that pin instead of the quest. Distance and text refer to the pin.
Corpse navigation still takes priority while dead. When pin navigation is
cleared, quest navigation resumes; with neither selected, the arrow hides.
An unselected pin merely present on the map does not override the quest.
User waypoints can fall back to their stored map coordinates if the navigation
API has no route. Built-in pins require the game's navigation waypoint data.

NEW IN 1.1.3
Fixes map-pin errors when the client returns plain {x, y} position tables
instead of Vector2DMixin objects. Pin, corpse and world coordinate reads
now support both formats and safely handle unavailable coordinates.
