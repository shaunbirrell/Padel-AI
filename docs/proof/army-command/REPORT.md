# Army command bug (2026-10-01): root cause, fix, proof

Spec: /workspace/specs/army-command-bug-2026-10-01.md. Line numbers marked "old" refer to d17409f (v160 + instrumentation
only, no behaviour change); "new" refers to this ship.

## Root cause (proven, docs/proof/army-command/before-client.log, real MapController + OrdersController in the sim)
```
[ARMY SEND] SEND pressed: MapController.Open() MapMode=Normal (no army mode) ArmyId=470626172
[ARMY SEND] tap -> Area Town "Crossroads Town" card: GO only (SEND ARMY hidden: selectBase only)
[ARMY SEND] GO pressed MapMode=Normal ArmyId=nil BaseId=Area:Town Position=(0,0) Firing remote=none (pinAt: the PLAYER pin)
REMOTE RequestAnalyticsEvent ArmyOpened          <- the only remote fired
PIN 0 0 Pin=true                                 <- his "PIN 678m"
```
No [SERVER ARMY] line: the server never heard about it. The army SEND button opened the ordinary tap-to-pin map
(old OrdersController.luau:134-143 `pcall(MC.Open)`). A zone card only had GO (old MapController.luau:795 selectArea);
SEND ARMY existed only on another player's named base card (old :840 selectBase). GO ran `pinAt(s.X, s.Z)`, which pins a
waypoint for HIM, and closed the map (old :1427-1432). Even a remote with a zone could not have worked: the server
handler took plot ids only and returned silently on anything else (old ArmyPlan.luau:1040
`if id <= 0 or not live(...) then return`), and the RemoteGate schema was `{ "number" }`.

ATTACK "No enemies near" (old ArmyPlan.luau:666-680 thinkClear): ATTACK started a 250-stud seek around him; finding
nothing it toasted NothingNear, then marched "back" and FINISHED INTO FOLLOW (old :361 `st.Order = "Follow"`). So a
HOLDING army ended up FOLLOWING, and the client had already lit ATTACK on its own (old OrdersController.luau:160
`currentOrder = orderId`). That is the "broken Attack mode" the spec warns about.

## The 12 answers
1. Follow is driven by ArmyController.stepArmy (Follow3, a 0.2 s loop) -> SoldierController.Drive (MoveTo to the slot
   behind him), plus SquadOrdersService.thinkUnit's Follow branch (old :3218, a 0.4 s loop: escort / follow / recover)
   and Modules/ArmyFollow.
2. Send: client OrdersController.fireOrder("Send") -> MapController; server ArmyPlan (StartSend for bases; now also
   StartTravel for zones and sites) via ArmyCommand.Send.
3. OrdersController.fireOrder("Send") opened the map with plain MapController.Open() (old :143). Now it calls
   MapController.OpenForArmySend().
4. MapController goB.Activated (old :1427). In normal mode it pins and closes. Now, in ArmySend mode, it fires
   RequestArmySend(target id).
5. RequestSquadOrder (Follow / Hold / Attack / Retreat / Recall) and RequestArmySend (send). RequestArmySendCheck gives
   the verdict preview.
6. SquadOrdersService `squadByUser[userId]` (st.Order, old :194), with the plan in ArmyPlan `plans[userId]`. Now the
   state lives in st.ArmyState / st.Order, written only by Modules/ArmyState.Set, and is mirrored to the WE_ArmyState
   attribute and the SquadOrderStateUpdate.State field.
7. Things that can change the army destination:
   - ArmyController/SoldierController.Drive (his slot, or ArmyPlan's lead point)
   - thinkUnit Hold/Retreat (ArmyFollow.Command)
   - attackUnit, escortUnit, followMove, recoverUnit and _PaceRecover (PivotTo emergency, Follow only)
   - ArmyPlan setDest/advance
   - SoldierController.Reposition (off during plans)
   - the SyncArmy spawn
   The player pin (ObjectiveMarker) is client-only and never touches the army.
8. Yes. Follow stayed, because no army command ever reached the server.
9. Yes. GO called pinAt (the ordinary player pin).
10. No. Nothing was fired (see the log above).
11. Never. The state did not exist. The nearest thing, the ArmyPlan Send march, was only reachable for player bases.
12. Nothing ran that could overwrite it. Latent risks, now removed:
    - ArmyPlan.Think rewrote st.Order = "Attack" on every tick (old :929).
    - The client highlight was a guess, not the server's state.

## After (docs/proof/army-command/after-*.log)
```
[ARMY SEND] SEND pressed: MapController.OpenForArmySend() MapMode=ArmySend ArmyId=470626172
[ARMY SEND] tap -> Area Town "Crossroads Town" MapMode=ArmySend card button=SEND ARMY (RequestArmySend A:Town)
[ARMY SEND] GO pressed MapMode=ArmySend ArmyId=470626172 BaseId=A:Town Position=(0,0) Firing remote=RequestArmySend
[SERVER ARMY] received player=shaunie6 command=Send target=A:Town
[ARMY DESTINATION] ... -> (-100,1,0)   [ARMY PATH] ... status=Success
[ARMY STATE] shaunie6 Following -> TravellingToBase SOURCE=SEND A:Town
[ARMY MOVE] travel started -> A:Town (Crossroads Town) approach=(-100,1,0) objective=(0,1,0)
... arrived ... EngagingTarget ... clear ... Holding
```
