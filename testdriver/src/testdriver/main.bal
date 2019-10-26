import ballerina/io;
import ballerina/http;
import ballerina/lang.'int;
import ballerina/time;

map<NNationalResult> allresults = {};

public function main(string resultsURL) returns error? {
    // load presidential election data from Nuwan
    check loadData();

    // send some results to the results system
    http:Client resultsSystem = new (resultsURL);
    NNationalResult? nr = allresults["2015"];
    if nr is () {
        return error("2015 results are not there");
    } else {
        io:println("Posting summary results");
        while true {
            int edNum = check readInt("\nEnter polling district code (0-21) or -1 to exit: ");
            if edNum == -1 {
                break;
            }
            if edNum < 0 || edNum > 21 {
                io:println("Bad ED entered!");
                continue;
            }
            NEDResult ner = nr.by_ed[edNum];
            int maxPDnum = ner.by_pd.length() - 1;
            int pdNum = check readInt("Enter PD number from district (0-" + maxPDnum.toString() + "): ");
            if pdNum < 0 || pdNum > maxPDnum {
                io:println("Bad PD entered");
                continue;
            }
            NPDResult npr = ner.by_pd[pdNum];
            string resCode = "SUMMARY--" + edNum.toString() + "--" + pdNum.toString();
            NSummaryStats ns = npr.summary_stats;
            PartyResult[] by_party = 
                npr.by_party.map(
                    x => <PartyResult>{ 
                            party: x.party,
                            candidate: x.candidate,
                            votes: x.votes,
                            percentage: getPercentage(x.votes, ns.total_polled)
                        });

            // convert to right format
            PresidentialResult sr = {
                    'type : PRESIDENTIAL_RESULT,
                    timestamp: check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ"),
                    level: "POLLING-DIVISION",
                    ed_code: edNum.toString(),
                    ed_name: ner.ed_name,
                    pd_code: pdNum.toString(),
                    pd_name: npr.pd_name,
                    by_party: by_party,
                    summary: {
                        valid: ns.valid_votes,
                        rejected: ns.rejected_votes,
                        polled: ns.total_polled,
                        electors: ns.registered_voters
                    }
            };

            json jj = check json.constructFrom(sr);
            io:println("posting to /result/data/: resCode=" + resCode + "; data=" + jj.toJsonString());
            var res = check resultsSystem->post ("/result/data/" + resCode, jj);
        }
    }

    io:println("ALL DONE: press ^C to exit (not sure why!)");
}

// return %ge with 2 digits precision
function getPercentage (int votes, int total_polled) returns decimal {
    float f;

    f = (votes*10000.0)/total_polled;
    int i = <int> f;
    return <decimal> i/100;
}

function loadData() returns error? {
    service svc = 
        @http:ServiceConfig {
            basePath: "/"
        }
        service {
            @http:ResourceConfig {
                methods: ["POST"],
                path: "/{year}",
                body: "result"
            }
            resource function data(http:Caller caller, http:Request req, string year, NNationalResult result) returns error? {
                allresults[<@untainted> year] = <@untainted> result;
                io:println("Received data for election year: " + year);
                check caller->ok ("Thanks!");
            }
        };

    http:Listener hl = new(4444);
    check hl.__attach(svc);
    check hl.__start();
    _ = io:readln("POST json data to http://localhost:4444/YEAR now and hit RETURN to continue!");
    if allresults.length() == 0 {
        io:println("No results received!");
        return error("No results received");
    }
    check hl.__detach(svc);
    check hl.__immediateStop();
}

function readInt (string msg) returns int | error {
    string input = io:readln(msg);
    return <@untainted> 'int:fromString(input);
}