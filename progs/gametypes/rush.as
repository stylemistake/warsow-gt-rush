/*
Copyright (C) 2009-2010 Chasseur de bots
Copyright (C) 2015 Pepper

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

const int RUSH_penalty_PER_SEC = 1;
const int RUSH_ITEMS_MASK = (IT_WEAPON | IT_AMMO | IT_HEALTH);
const array<int> RUSH_PRIMARY_WEAPONS = {
    WEAP_ROCKETLAUNCHER,
    WEAP_ELECTROBOLT,
    WEAP_LASERGUN
};
const array<int> RUSH_SECONDARY_WEAPONS = {
    WEAP_MACHINEGUN,
    WEAP_RIOTGUN,
    WEAP_GRENADELAUNCHER,
    WEAP_PLASMAGUN
};

class Timer {
    String name;
    int interval; // in seconds
    int time; // real time snapshot

    Timer(String name, int interval) {
        this.name = name;
        this.interval = interval > 0 ? interval : 1;
        this.time = realTime;
    }

    ~Timer() {}
}

class TimersManager {
    array<Timer@> timers;

    TimersManager() {}
    ~TimersManager() {}

    void addInterval(String name, int interval) {
        this.timers.insertLast(Timer(name, interval));
    }

    Timer@ getTimerByName(String name) {
        Timer @timer;

        for (uint i = 0; i < this.timers.length(); i++) {
            if (this.timers[i].name == name) {
                @timer = this.timers[i];
            }
        }

        return @timer;
    }

    bool isIntervalPassed(String name) {
        Timer @timer = getTimerByName(name);

        if (@timer == null) {
            return false;
        }

        int currentTime = realTime;
        int diff = currentTime - timer.time;

        if (diff >= timer.interval) {
            timer.time = currentTime;
            return true;
        }

        return false;
    }
}

TimersManager timersManager;

// -----------------------------------------------------------------
//  NEW MAP ENTITY DEFINITIONS
// -----------------------------------------------------------------

// -----------------------------------------------------------------
//  LOCAL FUNCTIONS
// -----------------------------------------------------------------

// a player has just died. The script is warned about it so it can account scores
void DM_playerKilled(Entity @target, Entity @attacker, Entity @inflicter) {
    if (match.getState() != MATCH_STATE_PLAYTIME) {
        return;
    }

    if (@target.client == null) {
        return;
    }

    // drop items
    if ((G_PointContents(target.origin) & CONTENTS_NODROP) == 0) {
        Item @item;
        Item @ammoItem;

        for (int i = WEAP_GUNBLADE + 1; i < WEAP_TOTAL; i++) {
            if (attacker.client.inventoryCount(i) != 0) {
                @item = @G_GetItem(i);
                @ammoItem = @G_GetItem(item.ammoTag);
                target.dropItem(ammoItem.tag);
            }
        }

        if (attacker.weapon == WEAP_GUNBLADE) {
            target.dropItem(HEALTH_MEGA);
        }
    }

    award_playerKilled(@target, @attacker, @inflicter);
}

// -----------------------------------------------------------------
//  MODULE SCRIPT CALLS
// -----------------------------------------------------------------

bool GT_Command(Client @client, const String &cmdString, const String &argsString, int argc) {
    if (cmdString == "cvarinfo") {
        GENERIC_CheatVarResponse(client, cmdString, argsString, argc);
        return true;
    }

    // example of registered command
    if (cmdString == "gametype") {
        String response = "";
        Cvar fs_game("fs_game", "", 0);
        String manifest = gametype.manifest;

        response += "\n";
        response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
        response += "----------------\n";
        response += "Version: " + gametype.version + "\n";
        response += "Author: " + gametype.author + "\n";
        response += "Mod: " + fs_game.string + (!manifest.empty() ? " (manifest: " + manifest + ")" : "") + "\n";
        response += "----------------\n";

        G_PrintMsg(client.getEnt(), response);
        return true;
    }

    if (cmdString == "callvotevalidate") {
        String votename = argsString.getToken(0);
        client.printMessage("Unknown callvote " + votename + "\n");
        return false;
    }

    if (cmdString == "callvotepassed") {
        String votename = argsString.getToken(0);
        return true;
    }

    return false;
}

// When this function is called the weights of items have been reset to their default values,
// this means, the weights *are set*, and what this function does is scaling them depending
// on the current bot status.
// Player, and non-item entities don't have any weight set. So they will be ignored by the bot
// unless a weight is assigned here.
bool GT_UpdateBotStatus(Entity @self) {
    return GENERIC_UpdateBotStatus(self);
}

// select a spawning point for a player
Entity @GT_SelectSpawnPoint(Entity @self) {
    return GENERIC_SelectBestRandomSpawnPoint(self, "info_player_deathmatch");
}

String @GT_ScoreboardMessage(uint maxlen) {
    String scoreboardMessage = "";
    String entry;
    Team @team;
    Entity @ent;
    int i, carrierIcon, readyIcon;

    @team = @G_GetTeam(TEAM_PLAYERS);

    // &t = team tab, team tag, team score (doesn't apply), team ping (doesn't apply)
    entry = "&t " + int(TEAM_PLAYERS) + " " + team.stats.score + " 0 ";
    if (scoreboardMessage.len() + entry.len() < maxlen) {
        scoreboardMessage += entry;
    }

    for (i = 0; @team.ent(i) != null; i++) {
        @ent = @team.ent(i);

        if (ent.client.isReady()) {
            readyIcon = G_ImageIndex("gfx/hud/icons/vsay/yes");
        } else {
            readyIcon = 0;
        }

        int playerID = (ent.isGhosting() && (match.getState() == MATCH_STATE_PLAYTIME))
            ? -(ent.playerNum + 1)
            : ent.playerNum;

        entry = "&p " + playerID + " " + ent.client.clanName + " "
            + ent.client.stats.score + " " + ent.client.ping
            + " " + readyIcon + " ";

        if (scoreboardMessage.len() + entry.len() < maxlen) {
            scoreboardMessage += entry;
        }
    }

    return scoreboardMessage;
}

// Some game actions trigger score events. These are events not related to killing
// oponents, like capturing a flag
// Warning: client can be null
void GT_ScoreEvent(Client @client, const String &score_event, const String &args) {
    Entity @attacker = @client.getEnt();
    Entity @target = @G_GetEntity(args.getToken(0).toInt());
    int damage = args.getToken(1).toInt();

    if (score_event == "dmg") {
        // Don't count score if match didn't start yet.
        if (match.getState() != MATCH_STATE_PLAYTIME) {
            return;
        }
        if (@client != null) {
            // Subtract self damage from score
            if (attacker.playerNum == target.playerNum) {
                damage = -damage;
            }
            if (damage > target.health) {
                // Too much damage, cap at target's health
                // Covers telefrags
                damage = int(target.health);
            }
            if (client.stats.score + damage > 0) {
                client.stats.addScore(damage);
            } else {
                // Don't set negative scores
                client.stats.setScore(0);
            }
        }
        return;
    }

    if (score_event == "kill") {
        Entity @attacker = null;

        if (@client != null) {
            @attacker = @client.getEnt();
        }

        int arg1 = args.getToken(0).toInt();
        int arg2 = args.getToken(1).toInt();

        // target, attacker, inflictor
        DM_playerKilled(G_GetEntity(arg1), attacker, G_GetEntity(arg2));
        return;
    }

    if (score_event == "award") {
        return;
    }
}

void giveGun(Entity @ent, int weapon) {
    ent.client.inventoryGiveItem(weapon);
    Item @item = @G_GetItem(weapon);
    Item @ammoItem = @G_GetItem(item.ammoTag);
    if (@ammoItem != null) {
        ent.client.inventorySetCount(ammoItem.tag, ammoItem.inventoryMax);
    }
}

// a player is being respawned. This can happen from several ways, as dying, changing team,
// being moved to ghost state, be placed in respawn queue, being spawned from spawn queue, etc
void GT_PlayerRespawn(Entity @ent, int old_team, int new_team) {
    if (ent.isGhosting()) {
        return;
    }

    if (gametype.isInstagib) {
        ent.client.inventoryGiveItem(WEAP_INSTAGUN);
        ent.client.inventorySetCount(AMMO_INSTAS, 1);
        ent.client.inventorySetCount(AMMO_WEAK_INSTAS, 1);
    } else {
        Item @item;
        Item @ammoItem;

        // the gunblade can't be given (because it can't be dropped)
        ent.client.inventorySetCount(WEAP_GUNBLADE, 1);

        @item = @G_GetItem(WEAP_GUNBLADE);

        @ammoItem = @G_GetItem(item.ammoTag);
        if (@ammoItem != null) {
            ent.client.inventorySetCount( ammoItem.tag, ammoItem.inventoryMax );
        }

        ent.maxHealth = 200;
        ent.health = 200;
        // ent.client.armor = 125;

        uint index;

        // give primary gun #1
        index = uint(brandom(0, RUSH_PRIMARY_WEAPONS.length()));
        giveGun(ent, RUSH_PRIMARY_WEAPONS[index]);

        // // give primary gun #2
        // if (index == RUSH_PRIMARY_WEAPONS.length() - 1) {
        //     giveGun(ent, RUSH_PRIMARY_WEAPONS[0]);
        // } else {
        //     giveGun(ent, RUSH_PRIMARY_WEAPONS[index+1]);
        // }

        // give secondary gun
        index = uint(brandom(0, RUSH_SECONDARY_WEAPONS.length()));
        giveGun(ent, RUSH_SECONDARY_WEAPONS[index]);
    }

    // select rocket launcher if available
    ent.client.selectWeapon(-1); // auto-select best weapon in the inventory

    // add a teleportation effect
    ent.respawnEffect();
}

// Thinking function. Called each frame
void GT_ThinkRules() {
    if (match.scoreLimitHit() || match.timeLimitHit() || match.suddenDeathFinished()) {
        match.launchState(match.getState() + 1);
    }

    if (match.getState() >= MATCH_STATE_POSTMATCH) {
        return;
    }

    GENERIC_Think();

    Entity @ent;

    for (int i = 0; i < maxClients; i++) {
        @ent = @G_GetClient(i).getEnt();

        // // Drain health if more than 100
        // if (ent.health > 100) {
        //     ent.health -= ( frameTime * 0.001f );
        // }

        // Charge gunblade
        if (ent.client.state() >= CS_SPAWNED && ent.team != TEAM_SPECTATOR) {
            GENERIC_ChargeGunblade(ent.client);
        }
    }

    if (timersManager.isIntervalPassed("penalty")) {
        for (int i = 0; i < maxClients; i++) {
            @ent = @G_GetClient(i).getEnt();
            if (ent.client.state() >= CS_SPAWNED && ent.team != TEAM_SPECTATOR) {
                if (ent.client.stats.score > RUSH_penalty_PER_SEC) {
                    ent.client.stats.addScore(-RUSH_penalty_PER_SEC);
                } else {
                    ent.client.stats.setScore(0);
                }
            }
        }
    }
}

// The game has detected the end of the match state, but it
// doesn't advance it before calling this function.
// This function must give permission to move into the next
// state by returning true.
bool GT_MatchStateFinished(int incomingMatchState) {
    if (match.getState() <= MATCH_STATE_WARMUP
            && incomingMatchState > MATCH_STATE_WARMUP
            && incomingMatchState < MATCH_STATE_POSTMATCH) {
        match.startAutorecord();
    }

    if (match.getState() == MATCH_STATE_POSTMATCH) {
        match.stopAutorecord();
    }

    return true;
}

// the match state has just moved into a new state. Here is the
// place to set up the new state rules
void GT_MatchStateStarted() {
    switch (match.getState()) {
        case MATCH_STATE_WARMUP:
            gametype.pickableItemsMask = RUSH_ITEMS_MASK;
            gametype.dropableItemsMask = RUSH_ITEMS_MASK;
            GENERIC_SetUpWarmup();
            SpawnIndicators::Create("info_player_deathmatch", TEAM_PLAYERS);
            break;

        case MATCH_STATE_COUNTDOWN:
            gametype.pickableItemsMask = 0; // disallow item pickup
            gametype.dropableItemsMask = 0; // disallow item drop
            GENERIC_SetUpCountdown();
            SpawnIndicators::Delete();
            break;

        case MATCH_STATE_PLAYTIME:
            gametype.pickableItemsMask = RUSH_ITEMS_MASK;
            gametype.dropableItemsMask = RUSH_ITEMS_MASK;
            GENERIC_SetUpMatch();
            break;

        case MATCH_STATE_POSTMATCH:
            gametype.pickableItemsMask = 0; // disallow item pickup
            gametype.dropableItemsMask = 0; // disallow item drop
            GENERIC_SetUpEndMatch();
            break;

        default:
            break;
    }
}

// the gametype is shutting down cause of a match restart or map change
void GT_Shutdown() {
}

// The map entities have just been spawned. The level is initialized for
// playing, but nothing has yet started.
void GT_SpawnGametype() {
}

// Important: This function is called before any entity is spawned, and
// spawning entities from it is forbidden. If you want to make any entity
// spawning at initialization do it in GT_SpawnGametype, which is called
// right after the map entities spawning.

void GT_InitGametype() {
    gametype.title = "Rush Deathmatch";
    gametype.version = "1.2.1";
    gametype.author = "Pepper";

    // if the gametype doesn't have a config file, create it
    if (!G_FileExists("configs/server/gametypes/" + gametype.name + ".cfg")) {
        String config;

        // the config file doesn't exist or it's empty, create it
        config = "// '" + gametype.title + "' gametype configuration file\n"
                 + "// This config will be executed each time the gametype is started\n"
                 + "\n\n// map rotation\n"
                 + "set g_maplist \"wda1 wda2 wda3 wda4 wda5\" // list of maps in automatic rotation\n"
                 + "set g_maprotation \"1\"   // 0 = same map, 1 = in order, 2 = random\n"
                 + "\n// game settings\n"
                 + "set g_scorelimit \"0\"\n"
                 + "set g_timelimit \"15\"\n"
                 + "set g_warmup_timelimit \"1\"\n"
                 + "set g_match_extendedtime \"0\"\n"
                 + "set g_allow_falldamage \"0\"\n"
                 + "set g_allow_selfdamage \"0\"\n"
                 + "set g_allow_teamdamage \"0\"\n"
                 + "set g_allow_stun \"1\"\n"
                 + "set g_teams_maxplayers \"0\"\n"
                 + "set g_teams_allow_uneven \"0\"\n"
                 + "set g_countdown_time \"5\"\n"
                 + "set g_maxtimeouts \"3\" // -1 = unlimited\n"
                 + "\necho \"" + gametype.name + ".cfg executed\"\n";

        G_WriteFile("configs/server/gametypes/" + gametype.name + ".cfg", config);
        G_Print("Created default config file for '" + gametype.name + "'\n");
        G_CmdExecute("exec configs/server/gametypes/" + gametype.name + ".cfg silent");
    }

    gametype.spawnableItemsMask = 0;
    gametype.respawnableItemsMask = 0;
    gametype.dropableItemsMask = RUSH_ITEMS_MASK;
    gametype.pickableItemsMask = RUSH_ITEMS_MASK;

    gametype.isTeamBased = false;
    gametype.isRace = false;
    gametype.hasChallengersQueue = false;
    gametype.maxPlayersPerTeam = 0;

    gametype.ammoRespawn = 0;
    gametype.armorRespawn = 0;
    gametype.weaponRespawn = 0;
    gametype.healthRespawn = 0;
    gametype.powerupRespawn = 0;
    gametype.megahealthRespawn = 0;
    gametype.ultrahealthRespawn = 0;

    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    gametype.mathAbortDisabled = false;
    gametype.shootingDisabled = false;
    gametype.infiniteAmmo = false;
    gametype.canForceModels = true;
    gametype.canShowMinimap = false;
    gametype.teamOnlyMinimap = false;

    gametype.mmCompatible = true;

    gametype.spawnpointRadius = 256;

    if (gametype.isInstagib) {
        gametype.spawnpointRadius *= 2;
    }

    // set spawnsystem type
    for (int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++) {
        gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_INSTANT, 0, 0, false );
    }

    // define the scoreboard layout
    G_ConfigString(CS_SCB_PLAYERTAB_LAYOUT, '%n 112 %s 52 %i 52 %l 48 %p 18');
    G_ConfigString(CS_SCB_PLAYERTAB_TITLES, 'Name Clan Score Ping R');

    // add commands
    G_RegisterCommand("gametype");

    G_Print("Gametype '" + gametype.title + "' initialized\n");

    timersManager.addInterval("penalty", 1000);
}
