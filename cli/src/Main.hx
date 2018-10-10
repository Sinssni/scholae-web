package ;

import sys.db.Types.SBigInt;
import model.Attempt;
import model.CodeforcesTaskTag;
import model.CodeforcesTag;
import model.CodeforcesUser;
import model.NeercUser;
import model.NeercTeam;
import model.NeercTeamUser;
import model.NeercContest;
import codeforces.Problem;
import codeforces.Codeforces;
import codeforces.Contest;
import codeforces.Submission;
import haxe.ds.IntMap;
import model.CodeforcesTask;
import codeforces.ProblemStatistics;
import haxe.ds.StringMap;
import codeforces.ProblemsResponse;
import codeforces.Codeforces;
import parser.Neerc;
import parser.CodeforcesUsers;
import haxe.EnumTools;
import haxe.EnumTools.EnumValueTools;
import haxe.Json;


enum Action {
    updateCodeforcesTasks;
    updateCodeforcesTasksLevelsAndTypes;
    updateGymTasks;
    updateTags;
    updateTaskIdsOnAttempts;
    updateNeercData;
    updateCodeforcesUsersHandles;
    updateCodeforcesUsersNames;
    updateNeercUsersRelationWithCodeforces;
}

typedef Config = {
    action: Action,
    batchCount: Int,
    verbose: Bool,
    year: String
}


class Main {

    private static var cfg: Config;

    public static function main() {

        var cnx = sys.db.Mysql.connect({
            host : "127.0.0.1",
            port : null,
            user : "scholae",
            pass : "scholae",
            database : "scholae",
            socket : null,
        });
        cnx.request("SET NAMES 'utf8';");

        sys.db.Manager.cnx = cnx;
        sys.db.Manager.initialize();

        cfg = { action: null, batchCount: 100, verbose: false, year: null };

        var args = Sys.args();
        var argHandler = hxargs.Args.generate([
            @doc("Action: updateCodeforcesTasks, updateCodeforcesTasksLevelsAndTypes, updateGymTasks, updateTags, updateTaskIdsOnAttempts, updateNeercData, updateCodeforcesUsersHandles, updateCodeforcesUsersNames, updateNeercUsersRelationWithCodeforces")
            ["-a", "--action"] => function(action:String) cfg.action = EnumTools.createByName(Action, action),

            @doc("Limit number of processing items. Works only for updateGymTasks")
            ["-c", "--count"] => function(count:String) cfg.batchCount = Std.parseInt(count),

            @doc("Enable the verbose mode")
            ["-v", "--verbose"] => function() cfg.verbose=true,

            @doc("Output Neerc users rating on Codeforces")
            ["-n", "--solved-problems"] => function(year:String) cfg.year = year,

            _ => function(arg:String) throw "Unknown command: " +arg
        ]);

        argHandler.parse(args);

        if (args.length <= 0) {
            Sys.println("Scholae command line tool");
            Sys.println(argHandler.getDoc());
            Sys.exit(0);
        }

        if (cfg.year != null) {
            updateNeercSolvedProblems(Std.parseInt(cfg.year));
            Sys.exit(0);
        }

        switch (cfg.action) {
            case Action.updateCodeforcesTasks: updateCodeforcesTasks();
            case Action.updateCodeforcesTasksLevelsAndTypes: updateCodeforcesTasksLevelsAndTypes();
            case Action.updateGymTasks: updateGymTasks(cfg);
            case Action.updateTags: updateTags();
            case Action.updateTaskIdsOnAttempts: updateTaskIdsOnAttempts();
            case Action.updateNeercData: updateNeercData();
            case Action.updateCodeforcesUsersHandles: CodeforcesUsers.ParseUsersFromRussia();
            case Action.updateCodeforcesUsersNames: CodeforcesUsers.updateCodeforcesUsersNames();
            case Action.updateNeercUsersRelationWithCodeforces: updateNeercUsersRelationWithCodeforces();
        }

        sys.db.Manager.cleanup();
        cnx.close();
    }

    public static function updateCodeforcesTasks() {
        updateCodeForcesTasksByResoponse(Codeforces.getAllProblemsResponse());

    }

    private static inline function getProblemId(contestId: Int, index: String): String {
        return Std.string(contestId) + "::" + index;
    }

    private static function updateCodeForcesTasksByResoponse(response: ProblemsResponse) {
        var statistics: StringMap<ProblemStatistics> =  new StringMap<ProblemStatistics>();

        for (s in response.problemStatistics) {
            statistics.set(getProblemId(s.contestId, s.index), s);
        }

        for (p in response.problems) {
            if (p.type != "PROGRAMMING") continue;
            var t: CodeforcesTask = CodeforcesTask.getOrCreateByCodeforcesProblem(p);
            var s = statistics.get(getProblemId(p.contestId, p.index));
            t.solvedCount = if (s != null) s.solvedCount else 0;
            t.update();
        }
    }

    public static function updateTaskIdsOnAttempts() {
        var isNull:Null<SBigInt> = null;
        var attempts = Attempt.manager.search($taskId == isNull);
        for (attempt in attempts) {
            var d = Json.parse(attempt.description);
            var contestId = Reflect.field(d,"contestId");
            var index = Reflect.field(d.problem,"index");
            var codeforcesTask = CodeforcesTask.manager.select({contestId: contestId, contestIndex: index});
            attempt.task = codeforcesTask;
            attempt.update();
        }
    }

    public static function updateCodeforcesTasksLevelsAndTypes() {

        var contests: IntMap<Contest> = new IntMap<Contest>();
        for (c in Codeforces.getAllContests()) {
            contests.set(c.id, c);
        }

        var tasksByContest: IntMap<Array<CodeforcesTask>> = new IntMap<Array<CodeforcesTask>>();
        var tasks = CodeforcesTask.manager.all();
        for (t in tasks) {
            if (!tasksByContest.exists(t.contestId)) {
                tasksByContest.set(t.contestId, []);
            }
            tasksByContest.get(t.contestId).push(t);
        }

        for (t in tasks) {
            if (cfg.verbose) neko.Lib.println("Task: " + t.toMessage());

            var contest = contests.get(t.contestId);

            if (contest == null) {
                t.lock();
                t.active = false;
                t.update();
                continue;
            }

            if (cfg.verbose) neko.Lib.println("Task contest: " + contest);

            t.type = contest.type;

            if (contest.difficulty != null) {
                var contestSum: Int = Lambda.fold(tasksByContest.get(t.contestId), function(t, sum) { return sum + t.solvedCount;}, 0);
                var contestMiddle = contestSum / Lambda.count(tasksByContest.get(t.contestId));

                if (t.solvedCount < contestMiddle - contestSum / 6) {
                    t.level = Std.int(Math.max(1, contest.difficulty + 1));
                } else if (t.solvedCount > contestMiddle + contestSum / 6) {
                    t.level = Std.int(Math.min(contest.difficulty - 1, 5));
                } else {
                    t.level = contest.difficulty;
                }
            } else {
                t.level =
                        if (t.solvedCount < 100) 5
                        else if (t.solvedCount < 1000) 4
                        else if (t.solvedCount < 5000) 3
                        else if (t.solvedCount < 20000) 2
                        else 1;
            }

            t.update();
        }
    }

    public static function updateGymTasks(cfg: Config) {
        var processed = 0;
        for (c in Codeforces.getGymContests()) {
            if (!CodeforcesTask.doTasksExistForContest(c.id)) {
                trace(c);
                updateCodeForcesTasksByResoponse(Codeforces.getGymProblemsByContest(c));
                processed += 1;
                if (processed >= cfg.batchCount) {
                    break;
                }
            }
        }
    }

    public static function updateTags() {

        var response = Codeforces.getAllProblemsResponse();
        var problemFromResponse: StringMap<Problem> = new StringMap<Problem>();

        for (p in response.problems) {
            problemFromResponse.set(getProblemId(p.contestId, p.index), p);
        }

        var tasks = CodeforcesTask.manager.all();
        for (task in tasks) {
            var p = problemFromResponse.get(getProblemId(task.contestId, task.contestIndex));

            if (p != null && p.tags != null) {
                for (t in p.tags) {
                    var tag = CodeforcesTag.getOrCreateByName(t);
                    var relation = CodeforcesTaskTag.manager.get({ taskId: task.id, tagId: tag.id });
                    if (relation == null) {
                        relation = new CodeforcesTaskTag();
                        relation.task = task;
                        relation.tag = tag;
                        relation.insert();
                    }
                }
            }
        }
    }

    public static function updateNeercData() {
        var firstYear = 2010;
        var lastYear = 2017;

        for (year in firstYear...lastYear+1) {
            Neerc.startParsing("http://neerc.ifmo.ru/archive/" + (firstYear+(lastYear-year)) + "/standings.html", (firstYear+(lastYear-year)));
        }
    }

    public static function updateNeercUsersRelationWithCodeforces() {
        var codeforcesUsersList = Lambda.array(CodeforcesUser.manager.all());
        var neercUsersList = Lambda.array(NeercUser.manager.all());
        var codeforcesUsers: Array<String> = Lambda.array(Lambda.map(codeforcesUsersList, function(user) {
            return user.lastName;
        }));
        var neercUsers: Array<String> = Lambda.array(Lambda.map(neercUsersList, function(user) {
            return user.lastName;
        }));
        var indexes: Array<Int> = [];
        var updated = 0;

        for (i in 0...neercUsers.length) {
            if (neercUsers[i] != "null") {
                var index = codeforcesUsers.indexOf(neercUsers[i]);

                if (index != -1 && indexes.indexOf(index) == -1) {
                    var neerc = NeercUser.manager.select({id: neercUsersList[i].id});
                    neerc.codeforcesUsersId = index + 1;
                    neerc.update();

                    indexes.push(index);
                    updated++;
                }
            }
        }
        trace("Updated " + updated + " records");
    }

    public static function updateUserSolvedProblemsByHandle(handle: String): Int {
        var heh: Array<Submission> = Codeforces.getUserSubmissions(handle);
        var problems = 0;

        if (heh.length > 0) {
            for (i in 0...heh.length) {
                if (heh[i].verdict == "OK") {
                    problems++;
                }
            }

            var user = CodeforcesUser.manager.select($handle == handle, true);

            if (user != null) {
                user.solvedProblems = problems;
                user.update();
            }
        }

        return problems;
    }

    public static function updateNeercSolvedProblems(year: Int) {
        var contest = NeercContest.manager.select($year == year, true);

        if (contest != null) {
            var teams: Array<NeercTeam> = Lambda.array(NeercTeam.manager.search($contestId == contest.id, false));

            if (teams != null) {
                for (i in 0...teams.length) {
                    var members = NeercTeamUser.manager.search($teamId == teams[i].id, true);

                    if (members != null) {
                        trace(teams[i].rank + ". " + teams[i].name + ":");

                        if (members.first().user.codeforcesUsersId != null) {
                            trace(updateUserSolvedProblemsByHandle(members.first().user.codeforcesUser.handle));
                        }

                        /*for (j in members) {
                            trace(j.toMessage());
                        }*/
                    }
                }

            }
        }
    }

    public static function getNeercPlaceByUserHandle(handle: String): Int {
        var user = CodeforcesUser.manager.select($handle == handle, true);

        if (user != null) {
            var neercUser = NeercUser.manager.select($codeforcesUsersId == user.id, true);

            if (neercUser != null) {
                var teams = NeercTeamUser.manager.select($userId == neercUser.id);

                if (teams != null) {
                    var team = NeercTeam.manager.select($id == teams.teamId);

                    if (team != null) {
                        return team.rank;
                    }
                }
            }
        }

        return 0;
    }
}
