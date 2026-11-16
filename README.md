# Ballest Party Mode 0.4.0-beta.2

Public test beta for **2–4 players total, including the host**. Every player adds one object, everyone races a local copy
of the same cumulative track, and the round ends with a named multi-ghost replay that reveals placements at the finish.

## Install and launch

1. Extract the complete ZIP to a normal folder. Do not run it from inside the ZIP.
2. Keep Steam running, close Ballest, and double-click **Start-Party-Mode.cmd**.
3. On the first launch, choose whether to add the **Ballest Party Mode** desktop shortcut.
4. In Ballest, open **ballest party mode** from the main menu.

After the first launch, you can start it by double-clicking the new desktop icon. The shortcut points to the launcher in
the extracted folder, so do not move or delete that folder afterward.

The launcher creates an isolated test runtime beside itself. It does not replace the original Ballest game binaries.
All participating players must use the same beta ZIP.

## Start a party

- The host selects **Host Party**, then **Invite Friend**, or shares **Copy Invite Code**.
- Other players accept the Steam invite or enter the code and select **Join Party**.
- The host chooses the race duration and number of rounds, then selects **Start** once.
- Each player chooses one of three random native editor objects, places it, optionally scales it uniformly from 90% to
  110%, and selects **Lock in object**.
- Checkpoints, starts/finishes, point lights and decals are excluded from the random object pool.
- Previous objects remain on the track for later rounds. Falls and retries do not reset the race clock.

## Test status — players wanted

**We are looking for the first two players to test one complete Party Mode session over Steam on two different PCs.**

Tested locally:

- strict Windows host builds and AngelScript compilation pass
- plugin API documentation and test coverage checks pass
- two isolated local game processes completed object exchange, identical cumulative maps, finish/DNF recording,
  two-ghost replay, five-second result hold and the transition to the next build
- configurable round count completed two short local both-DNF rounds and stopped after the configured final round
- the owner confirmed that the Steam invite dialog opens and an invite code is displayed

Not yet tested:

- accepting the invite and completing a full round on two physical PCs over Steam
- separate three-player and four-player sessions
- the newest full-palette object selection and 90–110% scaling in a complete remote session

If the test stops working, run **Collect-Logs.cmd** and send the generated report with a short description. Generated
reports are not included in this download.

## Current integration status

This public test ZIP includes the required development build of Ballest Plugin Manager and is independent of the open
[Plugin Manager PR #31](https://github.com/AnythingGoes-ballest/ballest-plugin-manager/pull/31). It is not yet available
in **Plugins → Browse**. PR #31 remains open for upstream review.

## License

The Party Mode plugin and authored `party_base.balledit` map are MIT licensed. The ZIP also includes the applicable
Ballest Plugin Manager and AngelScript license texts. Ballest itself and its assets are not redistributed.
