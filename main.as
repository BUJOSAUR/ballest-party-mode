// One party, repeated local races of the same cumulative PROTOTIP snapshot.
const string VERSION = "0.4.0-beta.5";
const double RESULTS_HOLD_SECONDS = 5;
const int MENU=0, BUILD_LOADING=1, BUILD=2, RACE_LOADING=3, COUNTDOWN=4, RACING=5, REPLAY_LOADING=6, WATCHING=7, STOPPED=8;
const int SOLO_BOT_LOADING=9, SOLO_BOT_COUNTDOWN=10, SOLO_BOT_DRIVING=11, SOLO_DONE=12;
const int PARTY_DONE=13;
int roundLimit=10;
int buildSeconds=60;
UI::Text@ roundsLabel;
UI::TextInput@ roundsInput;
UI::Button@ roundsApply;
array<UI::Button@> roundsPresets(3);
UI::Text@ buildLabel;
UI::TextInput@ buildInput;
UI::Button@ buildApply;
array<UI::Button@> buildPresets(3);
bool soloMode=false;
[Setting hidden]
bool AllowPrivateSolo=false;
double Max(double a,double b) { return a>b?a:b; }
UI::Window@ window;
UI::FooterButton@ menu;
UI::FooterButton@ footer;
UI::Text@ status;
UI::Text@ detail;
UI::Text@ result;
UI::Window@ raceHud;
UI::Text@ remainingText;
UI::Text@ durationLabel;
UI::TextInput@ durationInput;
UI::Button@ durationApply;
array<UI::Button@> durationPresets(3);
int raceSeconds=60;
UI::TextInput@ code;
UI::Button@ create;
UI::Button@ solo;
UI::Button@ invite;
UI::Button@ copyCode;
UI::Button@ joinButton;
UI::Button@ start;
UI::Button@ leave;
UI::Button@ commit;
UI::Button@ skipReplay;
UI::Button@ nextRound;
UI::Text@ buildLegend;
array<UI::Button@> choices(3);
array<UI::Image@> choiceIcons(3);
int phase=MENU, roundNumber=0, selected=-1;
string session, peerId, peerVersion, ownerId, lobbyId, errorText;
string ownReplay, otherReplay, mapHash, shownState;
string pendingPiece;
string notice;
double noticeUntil=0;
bool sessionActive=false, ownPlaced=false, otherPlaced=false, ownReady=false, otherReady=false;
bool ownReplayReady=false, otherReplayReady=false, ownDone=false, otherDone=false;
bool hostRevealed=false, guestRevealed=false;
bool nextRoundQueued=false;
bool ownTimedOut=false;
bool forceReplayReveal=false;
int appliedLayout=-1;
double phaseSince=0, buildDeadline=0, countdownAt=0, lastHello=-100, peerSeen=-100, lastUi=-100, leftSince=-1, inactiveSince=-1;
double missingFinishSince=-1;
int raceRestarts=0;

bool Hosting() { return Together::IsLobbyOwner(); }
bool CanSetDuration() { return phase==MENU && (Together::LobbyState()!="in lobby" || Hosting()); }
void SetDuration(int seconds)
{
    if (!CanSetDuration()) return;
    if (seconds<1 || seconds>600) { Notice("Enter a whole number from 1 to 600 seconds."); return; }
    raceSeconds=seconds; durationInput.value=""+seconds;
    if (Hosting()) Together::SetLobbyData("party_race_seconds",""+seconds);
}
void SetRounds(int count)
{
    if (!CanSetDuration()) return;
    if (count<1 || count>100) { Notice("Enter a whole number from 1 to 100 rounds."); return; }
    roundLimit=count; roundsInput.value=""+count;
    if (Hosting()) Together::SetLobbyData("party_rounds",""+count);
}
void SetBuildDuration(int seconds)
{
    if (!CanSetDuration()) return;
    if (seconds<10 || seconds>600) { Notice("Enter a whole number from 10 to 600 seconds."); return; }
    buildSeconds=seconds; buildInput.value=""+seconds;
    if (Hosting()) Together::SetLobbyData("party_build_seconds",""+seconds);
}
void ApplyBuildDuration()
{
    string text=buildInput.typed;
    if (text=="" || text.length()>3 || text.findFirstNotOf("0123456789")>=0) { Notice("Enter a whole number from 10 to 600 seconds."); return; }
    SetBuildDuration(parseInt(text));
}
void ApplyRounds()
{
    string text=roundsInput.typed;
    if (text=="" || text.length()>3 || text.findFirstNotOf("0123456789")>=0) { Notice("Enter a whole number from 1 to 100 rounds."); return; }
    SetRounds(parseInt(text));
}
void ApplyDuration()
{
    string text=durationInput.typed;
    if (text=="" || text.findFirstNotOf("0123456789")>=0 || text.length()>3) { Notice("Enter a whole number from 1 to 600 seconds."); return; }
    SetDuration(parseInt(text));
}
void Notice(const string &in text)
{
    notice=text; noticeUntil=Host::Time()+8;
}
void Phase(int value)
{
    phase=value; phaseSince=Host::Time(); lastUi=-100;
    if (value==RACE_LOADING) result.text="";
    Log::Info("PARTY phase=" + value + " round=" + roundNumber);
}
void Abort(const string &in reason)
{
    if (phase==STOPPED) return;
    errorText=reason; Phase(STOPPED);
    ResetTransport();
    PartyStage::End();
    if (!soloMode) Together::LeaveLobby();
    Hud::HideGame(false);
    raceHud.visible=false;
    Log::Error("PARTY stopped: " + reason);
    window.visible=true;
}
void NativeFail(const string &in action) { Abort(action + ": " + PartyStage::Error()); }
void NewRound(int number)
{
    if (number < 1 || number > 256) { Abort("This party has reached its round limit."); return; }
    string previous=result.text;
    int previousRound=roundNumber;
    roundNumber=number; selected=-1; ownPlaced=false; otherPlaced=false;
    ownReady=false; otherReady=false; ownReplayReady=false; otherReplayReady=false;
    ownDone=false; otherDone=false; ownReplay=""; otherReplay="";
    nextRoundQueued=false;
    ownTimedOut=false;
    forceReplayReveal=false;
    hostRevealed=false; guestRevealed=false;
    missingFinishSince=-1;
    mapHash=""; result.text=number>1 && previous!="" ? "Previous round "+previousRound+":\n"+previous : "";
    pendingPiece="";
    if (!soloMode) GroupNewRound();
    if (!PartyStage::OpenBuild(roundNumber)) { NativeFail("Loading the build phase"); return; }
    Phase(BUILD_LOADING); window.visible=true;
}
void Begin(const string &in token)
{
    bool ok=soloMode ? PartyStage::SoloBegin(token) : PartyStage::Reset(token);
    if (!ok) { NativeFail("PROTOTIP"); return; }
    if (!PartyStage::SetRaceLimit(raceSeconds)) { NativeFail("Race duration"); return; }
    session=token; ownerId=Together::LobbyOwnerId(); sessionActive=true;
    NewRound(1);
}
void SubmitPiece()
{
    if (!soloMode) { GroupSubmit(); return; }
    if (phase!=BUILD || ownPlaced) return;
    if (selected < 0) { selected=0; if (PartyStage::Choose(0)==0) { NativeFail("Object selection"); return; } }
    string item=PartyStage::Capture();
    if (item=="") { Notice(PartyStage::Error()); return; }
    if (!PartyStage::Append(item,true)) { NativeFail("Saving the object"); return; }
    ownPlaced=true;
    if (soloMode)
    {
        if (!PartyStage::SoloPlace()) { NativeFail("Placing the bot object"); return; }
        otherPlaced=true;
    }
    else SendBlob("P",item);
    Log::Info("PARTY committed native piece; round=" + roundNumber);
}
void BeginRaceLoad()
{
    if (phase!=BUILD || !ownPlaced || !otherPlaced) return;
    string snapshot=PartyStage::Snapshot();
    mapHash=PartyStage::Digest(snapshot);
    if (!soloMode) SendBlob("M",snapshot);
    if (!PartyStage::OpenRace(roundNumber)) { NativeFail("Loading the race"); return; }
    Phase(RACE_LOADING); ownReady=false; otherReady=false;
}
void BeginReplayLoad()
{
    if (ownReplay=="" || otherReplay=="" || phase==REPLAY_LOADING || phase==WATCHING) return;
    bool ok=PartyStage::PrepareSoloReplay(ownReplay,otherReplay);
    if (!ok) { NativeFail("Preparing the replay"); return; }
    ownReplayReady=false; otherReplayReady=false; Phase(REPLAY_LOADING);
}
void UpdateRound()
{
    if (!soloMode) { GroupRound(); return; }
    double now=Host::Time();
    if (phase==BUILD_LOADING)
    {
        if (PartyStage::BuildReady())
        {
            array<string>@ offered=PartyStage::Offers();
            array<string>@ icons=PartyStage::OfferIcons();
            for (uint i=0;i<3 && i<offered.length();i++) choices[i].label=offered[i];
            for (uint i=0;i<3 && i<icons.length();i++) choiceIcons[i].path=icons[i];
            if (offered.length()==3) Log::Info("PARTY offers="+offered[0]+"|"+offered[1]+"|"+offered[2]);
            buildDeadline=now+buildSeconds; Phase(BUILD);
        }
        else if (now-phaseSince>60) NativeFail("The build phase took too long to load");
    }
    if (phase==BUILD)
    {
        if (!soloMode && !ownPlaced && now>=buildDeadline) { SubmitPiece(); if (!ownPlaced) { NativeFail("The object could not be placed before the deadline"); return; } }
        if ((soloMode || Hosting()) && ownPlaced && otherPlaced && sendQueue.length()==0) BeginRaceLoad();
    }
    if (soloMode && phase==RACE_LOADING)
    {
        if (PartyStage::RaceReady()) { countdownAt=now+10; Phase(COUNTDOWN); }
        else if (now-phaseSince>90) NativeFail("The solo race could not load");
        return;
    }
    if (phase==COUNTDOWN && (Race::IsActive() || now>=countdownAt))
    {
        if (!PartyStage::StartRace()) { NativeFail("Starting the race"); return; }
        raceRestarts=Race::Restarts(); inactiveSince=-1; Phase(RACING); window.visible=false;
    }
    if (phase==RACING)
    {
        if (ownReplay=="")
        {
            string finished=PartyStage::FinishedReplay();
            if (finished!="")
            {
                ownReplay=finished; ownTimedOut=!Json::Bool(finished,"?PartyFinished",true); window.visible=true; lastUi=-100;
                if (ownTimedOut) { result.text="DNF - Time limit reached."; Log::Info("PARTY own DNF shown immediately"); }
                if (soloMode)
                {
                    if (!PartyStage::OpenRace(roundNumber+100)) { NativeFail("Loading the bot race"); return; }
                    Phase(SOLO_BOT_LOADING); return;
                }
                SendBlob("R",ownReplay);
            }
            else if (Race::IsComplete())
            {
                if (missingFinishSince<0) missingFinishSince=now;
                if (now-missingFinishSince>3) { Abort("The recording could not be saved. The round has ended."); return; }
            }
            else if (Race::Restarts()!=raceRestarts) { Abort("The race restarted outside Party Mode. The round has ended."); return; }
            else if (!Race::IsActive() && !Race::IsComplete() && now-phaseSince>10)
            {
                if (inactiveSince<0) inactiveSince=now;
                if (now-inactiveSince>8) { Abort("The race did not start or was interrupted."); return; }
            } else inactiveSince=-1;
        }
        BeginReplayLoad();
    }
    if (phase==SOLO_BOT_LOADING)
    {
        if (PartyStage::RaceReady()) { countdownAt=now+1; Phase(SOLO_BOT_COUNTDOWN); }
        else if (now-phaseSince>60) NativeFail("The bot race could not load");
    }
    if (phase==SOLO_BOT_COUNTDOWN && now>=countdownAt)
    {
        if (!PartyStage::StartRace() || !PartyStage::SoloDrive()) { NativeFail("Starting the bot race"); return; }
        Phase(SOLO_BOT_DRIVING);
    }
    if (phase==SOLO_BOT_DRIVING)
    {
        string finished=PartyStage::FinishedReplay();
        if (finished!="") { otherReplay=finished; BeginReplayLoad(); }
        else if (now-phaseSince>raceSeconds+15) Abort("The bot recording was not ready after the time limit.");
    }
    if (soloMode && phase==REPLAY_LOADING)
    {
        if (PartyStage::ReplayReady())
        {
            if (!PartyStage::StartReplay()) { NativeFail("Solo replay"); return; }
            Phase(WATCHING);
        }
        else if (now-phaseSince>60) NativeFail("The solo recordings could not load");
        return;
    }
    if (phase==WATCHING)
    {
        double clock=PartyStage::ReplayClock(), a=PartyStage::FinishTime(0), b=PartyStage::FinishTime(1);
        string hostName=soloMode?Together::OwnName():(Hosting()?Together::OwnName():PeerName());
        string guestName=soloMode?"Bot":(Hosting()?PeerName():Together::OwnName());
        string shown="";
        bool tie=Math::abs(a-b)<0.0005;
        bool aFinished=PartyStage::ReplayFinished(0), bFinished=PartyStage::ReplayFinished(1);
        if ((forceReplayReveal || !aFinished || clock>=a) && !hostRevealed) { hostRevealed=true; Log::Info("PARTY reveal host playback="+clock+" finish="+a+" reachedGoal="+(aFinished?"true":"false")); }
        if ((forceReplayReveal || !bFinished || clock>=b) && !guestRevealed) { guestRevealed=true; Log::Info("PARTY reveal guest playback="+clock+" finish="+b+" reachedGoal="+(bFinished?"true":"false")); }
        if (forceReplayReveal || !aFinished || clock>=a) shown+=hostName+(aFinished?" - "+(!bFinished || tie || a<=b?"1st":"2nd")+"  "+formatFloat(a,"",0,3)+" s"+(tie && bFinished?" (tie)":""):" - DNF")+"\n";
        if (forceReplayReveal || !bFinished || clock>=b) shown+=guestName+(bFinished?" - "+(!aFinished || tie || b<=a?"1st":"2nd")+"  "+formatFloat(b,"",0,3)+" s"+(tie && aFinished?" (tie)":""):" - DNF");
        result.text=shown;
        double lastFinish=Max(aFinished?a:0.0,bFinished?b:0.0);
        if (!ownDone && (forceReplayReveal || clock>=lastFinish))
        {
            if (!PartyStage::HoldReplay()) { NativeFail("Replay results"); return; }
            ownDone=true; if (!soloMode) Enqueue("DONE|"+session+"|"+roundNumber); phaseSince=now; lastUi=-100;
            Log::Info("PARTY results hold started; lastFinish="+lastFinish+" seconds="+RESULTS_HOLD_SECONDS);
        }
        if (soloMode)
        {
            if (ownDone && now-phaseSince>=RESULTS_HOLD_SECONDS)
            {
                if (roundNumber>=2) { sessionActive=false; Phase(SOLO_DONE); window.visible=true; UI::SetCursorVisible(true); }
                else NewRound(roundNumber+1);
            }
            else if (clock<0 && now-phaseSince>10 && !ownDone) NativeFail("The solo replay stopped unexpectedly");
            return;
        }

    }
}
string PeerName()
{
    array<string>@ ids=Together::LobbyMemberIds(); array<string>@ names=Together::LobbyMembers();
    for (uint i=0;i<ids.length() && i<names.length();i++) if (ids[i]==peerId) return names[i];
    return "Opponent";
}
void Refresh()
{
    bool showRaceHud=phase==RACING && ownReplay=="";
    if (raceHud.visible!=showRaceHud) raceHud.visible=showRaceHud;
    if (showRaceHud)
    {
        string remaining="TIME LEFT  "+int(Math::ceil(PartyStage::RaceRemaining()))+" s";
        if (remainingText.text!=remaining) remainingText.text=remaining;
    }
    durationLabel.text="Race duration: "+raceSeconds+" s"+(CanSetDuration()?" (1-600 s)":"");
    durationLabel.visible=phase==MENU;
    durationInput.visible=CanSetDuration(); durationApply.visible=CanSetDuration();
    for (uint i=0;i<3;i++) durationPresets[i].visible=CanSetDuration();
    roundsLabel.text="Multiplayer rounds: "+roundLimit+(CanSetDuration()?" (1-100)":"");
    roundsLabel.visible=phase==MENU;
    roundsInput.visible=CanSetDuration(); roundsApply.visible=CanSetDuration();
    for(uint i=0;i<3;i++) roundsPresets[i].visible=CanSetDuration();
    buildLabel.text="Build duration: "+buildSeconds+" s"+(CanSetDuration()?" (10-600 s)":"");
    buildLabel.visible=phase==MENU;
    buildInput.visible=CanSetDuration(); buildApply.visible=CanSetDuration();
    for(uint i=0;i<3;i++) buildPresets[i].visible=CanSetDuration();
    string text="Ballest Party Mode\n";
    if (phase==MENU) {
        text+=Together::LobbyState()=="in lobby" ? "Party: "+players.length()+"/4 players (2 required)" : "Create a party or join friends.";
        if (Together::LobbyState()=="in lobby") for(uint i=0;i<players.length();i++) {
            PartyLink@ link=players[i].id==Together::OwnId()?null:Link(players[i].id);
            bool connected=players[i].id==Together::OwnId() || (link !is null && link.version==VERSION && Host::Time()-link.seen<=15);
            text+="\n"+(i==0?"HOST  ":"PLAYER  ")+players[i].name+(players[i].id==Together::OwnId()?" (you)":"")+(connected?" - ready":" - connecting");
        }
    }
    if (phase==BUILD_LOADING) text+="Loading PROTOTIP - Round "+roundNumber+"/"+(soloMode?2:roundLimit);
    if (phase==BUILD) text+="Round "+roundNumber+"/"+roundLimit+" - "+(ownPlaced?"Waiting for all participants":"Choose and place one object: "+int(Math::ceil(Max(0.0,buildDeadline-Host::Time())))+" s");
    if (phase==BUILD && soloMode) text="Ballest Party Mode\nRound "+roundNumber+"/2 - Choose and place one object";
    if (phase==RACE_LOADING) text+="Loading the race...";
    if (phase==COUNTDOWN) text+="Press Play or wait. Auto-start in "+int(Math::ceil(Max(0.0,countdownAt-Host::Time())))+" s.";
    if (phase==RACING) text+=ownReplay=="" ? "Race to the finish" : (ownTimedOut?"Time limit reached - DNF":"Run complete")+"\nWaiting for all participants. Results are hidden.";
    if (phase==REPLAY_LOADING) text+="Preparing the replay...";
    if (phase==WATCHING) text+="Round "+roundNumber+"/"+(soloMode?2:roundLimit)+(ownDone?" - Results":" - Replay");
    if (phase==PARTY_DONE) text+="Party complete - "+roundLimit+" rounds";
    if (phase==STOPPED) text+="Party ended: "+errorText;
    if (phase==SOLO_BOT_LOADING || phase==SOLO_BOT_COUNTDOWN) text+="Preparing your opponent's run...";
    if (phase==SOLO_BOT_DRIVING) text+="Bot is racing. Your replay will begin shortly.";
    if (phase==SOLO_DONE) text+="Session complete";
    if (status.text!=text) status.text=text;
    bool inMenu=phase==MENU;
    bool showSolo=inMenu && AllowPrivateSolo;
    bool showCreate=inMenu && Together::LobbyState()!="in lobby";
    bool showInvite=inMenu && Hosting(), showCopy=inMenu && Together::LobbyState()=="in lobby";
    bool showStart=inMenu && Hosting(), showLeave=soloMode || Together::LobbyState()=="in lobby" || phase==STOPPED;
    if (solo.visible!=showSolo) solo.visible=showSolo;
    if (create.visible!=showCreate) create.visible=showCreate;
    if (invite.visible!=showInvite) invite.visible=showInvite;
    if (copyCode.visible!=showCopy) copyCode.visible=showCopy;
    if (code.visible!=inMenu) code.visible=inMenu;
    if (joinButton.visible!=inMenu) joinButton.visible=inMenu;
    if (start.visible!=showStart) start.visible=showStart;
    if (leave.visible!=showLeave) leave.visible=showLeave;
    for (uint i=0;i<3;i++)
    {
        bool showChoice=phase==BUILD && selected<0 && !ownPlaced;
        if (choices[i].visible!=showChoice) choices[i].visible=showChoice;
        if (choiceIcons[i].visible!=showChoice) choiceIcons[i].visible=showChoice;
    }
    bool showCommit=phase==BUILD && selected>=0 && !ownPlaced;
    if (commit.visible!=showCommit) commit.visible=showCommit;
    skipReplay.visible=phase==WATCHING && !ownDone;
    nextRound.visible=phase==WATCHING && ownDone && Hosting() && roundNumber<roundLimit;
    buildLegend.visible=phase==BUILD;
    string help;
    if (phase==MENU) help=Compatible()?"Players connected. The host can start the party.":"Invite friends or enter an invite code. 2-4 players including the host.";
    else if (phase==BUILD) help="Move the camera freely while this panel stays visible. Move, rotate and scale your object, then select Lock in object.";
    else if (phase==WATCHING && ownDone) help=((soloMode && roundNumber>=2) || (!soloMode && roundNumber>=roundLimit)?"Session complete in ":"Next round in ")+int(Math::ceil(Max(0.0,RESULTS_HOLD_SECONDS-(Host::Time()-phaseSince))))+" s.";
    else if (phase==WATCHING) {
        int votes=0;if(soloMode) votes=forceReplayReveal?1:0;else for(uint i=0;i<players.length();i++) if(players[i].skip) votes++;
        help="Placings appear as each ghost crosses the finish. Skip replay: "+votes+"/"+(soloMode?1:players.length())+" votes.";
    }
    else if (phase==PARTY_DONE) help="Final round results. Select End Party to return to the main menu.";
    else if (phase==SOLO_DONE) help="Two rounds completed. Select End Party to return to the main menu.";
    else if (phase==RACING && ownReplay=="") help="Retry as often as you need. Your clock keeps running.";
    else help="Rounds continue automatically.";
    if (phase==MENU && Together::LobbyState()!="none" && Together::LobbyState()!="in lobby")
        help="Connecting: "+Together::LobbyState();
    if (Host::Time()<noticeUntil && phase!=STOPPED) help=notice;
    if (soloMode && phase==BUILD && Host::Time()>=noticeUntil) help="Place your object, then select Lock in object. The bot drives straight.";
    if (detail.text!=help) detail.text=help;
    bool compactReplay=phase==WATCHING || phase==PARTY_DONE || phase==SOLO_DONE;
    int wantedLayout=compactReplay?1:0;
    if (appliedLayout!=wantedLayout && compactReplay)
    {
        window.SetAnchor(1,0.04f); window.SetPivot(1,0); window.SetOffset(-24,0);
        status.SetWidth(380); detail.SetWidth(380); result.SetWidth(380);
    }
    else if (appliedLayout!=wantedLayout)
    {
        window.SetAnchor(0.5f,0.08f); window.SetPivot(0.5f,0); window.SetOffset(0,0);
        status.SetWidth(600); detail.SetWidth(600); result.SetWidth(600);
    }
    appliedLayout=wantedLayout;
    // The native editor already owns its cursor. Requesting another UI cursor
    // changes input mode and locks its free camera, so leave it alone in BUILD.
    UI::SetCursorVisible(window.visible && phase!=BUILD);
}
void Main()
{
    Log::Info("PARTY HF2 hotfix: 10s native Play window; Exit ends party; Improve disabled; replay without native POV/menu timer");
    Log::Info("PARTY HF3 hotfix: results held 5s after last finish; End Party returns to main menu");
    Log::Info("PARTY HF4: continuous respawn/retry clock; configurable race deadline; DNF replays");
    Log::Info("PARTY HF5: English UI; immediate DNF; five-second hold after last actual finish");
    Log::Info("PARTY HF6: updated base track; temporary map cleanup; solo hidden by default");
    Log::Info("PARTY HF7: stable UI focus/cursor; centered race timer; clearer object lock action");
    Log::Info("PARTY beta.5 hotfix: editor legend; host-authoritative automatic next round; manual Next Round fallback");
    @window=UI::CreateWindow(); window.SetAnchor(0.5f,0.08f); window.SetPivot(0.5f,0);
    window.SetBackground(0.035f,0.05f,0.075f,0.95f); window.SetPadding(20,16);
    @status=window.AddText("Ballest Party Mode",22); window.NewRow();
    @detail=window.AddText("",15); window.NewRow();
    status.SetWidth(600); status.SetWrap(true); detail.SetWidth(600); detail.SetWrap(true);
    @create=window.AddButton("Host Party"); @invite=window.AddButton("Invite Friend"); @copyCode=window.AddButton("Copy Invite Code"); window.NewRow();
    @solo=window.AddButton("Play Solo"); window.NewRow();
    @durationLabel=window.AddText("Race duration: 60 s",17); window.NewRow();
    @durationPresets[0]=window.AddButton("30 s"); @durationPresets[1]=window.AddButton("60 s"); @durationPresets[2]=window.AddButton("90 s");
    @durationInput=window.AddTextInput(100,"Seconds"); durationInput.clearOnSubmit=false; durationInput.value="60";
    @durationApply=window.AddButton("Apply"); window.NewRow();
    @roundsLabel=window.AddText("Multiplayer rounds: 10",17); window.NewRow();
    @roundsPresets[0]=window.AddButton("5 rounds"); @roundsPresets[1]=window.AddButton("10 rounds"); @roundsPresets[2]=window.AddButton("20 rounds");
    @roundsInput=window.AddTextInput(100,"Rounds"); roundsInput.clearOnSubmit=false; roundsInput.value="10";
    @roundsApply=window.AddButton("Set Rounds"); window.NewRow();
    @buildLabel=window.AddText("Build duration: 60 s",17); window.NewRow();
    @buildPresets[0]=window.AddButton("30 s"); @buildPresets[1]=window.AddButton("60 s"); @buildPresets[2]=window.AddButton("120 s");
    @buildInput=window.AddTextInput(100,"Seconds"); buildInput.clearOnSubmit=false; buildInput.value="60";
    @buildApply=window.AddButton("Set Build Time"); window.NewRow();
    @code=window.AddTextInput(400,"BPM1: invite code"); code.clearOnSubmit=false; @joinButton=window.AddButton("Join Party"); window.NewRow();
    @start=window.AddButton("Start"); @leave=window.AddButton("End Party"); window.NewRow();
    for (uint i=0;i<3;i++) { @choiceIcons[i]=window.AddImage("",32,32); @choices[i]=window.AddButton("Object "+(i+1)); }
    window.NewRow(); @buildLegend=window.AddText("EDITOR CONTROLS   W  Move    E  Rotate    R  Scale",17); window.NewRow();
    @commit=window.AddButton("Lock in object"); @skipReplay=window.AddButton("Vote to Skip Replay"); @nextRound=window.AddButton("Next Round"); window.NewRow(); @result=window.AddText("",21);
    @menu=UI::AddMenuButton("ballest party mode"); @footer=UI::AddFooterButton("party mode"); window.visible=false;
    @raceHud=UI::CreateWindow(); raceHud.SetAnchor(0.5f,0.095f); raceHud.SetPivot(0.5f,0); raceHud.SetOffset(0,0);
    raceHud.SetBackground(0.035f,0.05f,0.075f,0.85f); raceHud.SetPadding(14,10);
    @remainingText=raceHud.AddText("TIME LEFT  60 s",26); raceHud.visible=false;
    Runs::SetKeep(20); Refresh();
}
void JoinCode()
{
    string value=code.typed;
    while (value.length()>0 && " \t\r\n".findFirst(value.substr(0,1))>=0) value=value.substr(1);
    while (value.length()>0 && " \t\r\n".findFirst(value.substr(value.length()-1,1))>=0) value=value.substr(0,value.length()-1);
    if (value.findFirst("BPM1:")==0) value=value.substr(5);
    if (value=="" || value.findFirstNotOf("0123456789")>=0) { Notice("Enter the BPM1: invite code from your friend."); return; }
    noticeUntil=0;
    Together::JoinLobby(value);
}
void Update(float dt)
{
    bool loading=phase==BUILD_LOADING || phase==RACE_LOADING || phase==SOLO_BOT_LOADING;
    if ((sessionActive || phase==SOLO_DONE) && !loading && UI::MainMenuShown() && !Race::OnTrack())
    {
        PartyStage::End(); Together::LeaveLobby(); ResetTransport();
        soloMode=false; sessionActive=false; session=""; lobbyId="";
        peerId=""; peerVersion=""; ownerId=""; errorText=""; result.text="";
        noticeUntil=0; Phase(MENU); window.visible=false; raceHud.visible=false; UI::SetCursorVisible(false);
        Log::Info("PARTY HF2 native Exit ended the party");
        return;
    }
    if (menu.Clicked() || footer.Clicked()) window.visible=!window.visible;
    if (CanSetDuration())
    {
        for (uint i=0;i<3;i++) if (durationPresets[i].Clicked()) SetDuration(int(i+1)*30);
        if (durationApply.Clicked() || durationInput.Submitted()) ApplyDuration();
        for(uint i=0;i<3;i++) if(roundsPresets[i].Clicked()) SetRounds(i==0?5:i==1?10:20);
        if(roundsApply.Clicked() || roundsInput.Submitted()) ApplyRounds();
        for(uint i=0;i<3;i++) if(buildPresets[i].Clicked()) SetBuildDuration(i==0?30:i==1?60:120);
        if(buildApply.Clicked() || buildInput.Submitted()) ApplyBuildDuration();
    }
    if (skipReplay.Clicked() && phase==WATCHING && !ownDone)
    {
        if (soloMode) forceReplayReveal=true;
        else { Participant@ mine=Me(); if (mine !is null && !mine.skip) { mine.skip=true; Enqueue("SKIP|"+session+"|"+roundNumber); } }
    }
    if (leave.Clicked())
    {
        PartyStage::End(true); Together::LeaveLobby(); ResetTransport();
        soloMode=false; sessionActive=false; session=""; lobbyId="";
        peerId=""; peerVersion=""; ownerId=""; errorText=""; result.text="";
        noticeUntil=0; nextRoundQueued=false; Phase(MENU); window.visible=false; raceHud.visible=false; UI::SetCursorVisible(false);
        Log::Info("PARTY HF3 End Party requested main menu");
        return;
    }
    if (solo.Clicked() && AllowPrivateSolo)
    {
        PartyStage::End(); Together::LeaveLobby(); ResetTransport();
        soloMode=true; errorText=""; noticeUntil=0;
        Begin(PartyStage::Digest("solo|"+Host::Time()).substr(0,24));
    }
    if (soloMode)
    {
        if (phase==BUILD && !ownPlaced)
        {
            for (uint i=0;i<3;i++) if (choices[i].Clicked() && selected<0) { if (PartyStage::Choose(i)==0) NativeFail("Object selection"); else selected=i; }
            if (commit.Clicked()) SubmitPiece();
        }
        if (sessionActive && phase!=STOPPED) UpdateRound();
        if (Host::Time()-lastUi>0.2) { lastUi=Host::Time(); Refresh(); }
        return;
    }
    GroupUpdate();
}
void OnDisabled() { UI::SetCursorVisible(false); PartyStage::End(); Hud::HideGame(false); Together::LeaveLobby(); }
