import path from "node:path";
import fs from "node:fs";

// check foundry version
async function checkForgeVersion(throwError = true) {
  let ciVersion = "";
  let localVersion = "";
  const wp = fs.readFileSync(
    path.join(process.cwd(), "./.gitea/workflows/ci.yml"),
    {
      encoding: "utf-8",
      flag: "r",
    }
  );

  const commit = wp.match(/nightly-([\dabcdef]+)/);
  if (commit) {
    ciVersion = commit[1].slice(0, 7);
  } else {
    throw "no foundry version found in preforge.ts";
  }

  const proc = Bun.spawn(["forge", "--version"], {});
  const stdout = await new Response(proc.stdout).text();
  const match = stdout.match(/\(([\dabcdef]{7})/);
  if (match) {
    localVersion = match[1];

    let matchDate = stdout.match(
      /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)/
    )?.[1];
    // @dev temp
    if (matchDate) {
      // if greater than 6/14/2024
      if (new Date(matchDate).getTime() > new Date(1718164800000).getTime()) {
        return;
      }
    }

    if (ciVersion !== localVersion) {
      console.log(
        "⚙️  forge version is out of date! Please update to version in /scripts/preforge.ts Install with:"
      );
      console.log(`foundryup -v nightly-${commit[1]}`);
      if (throwError) {
        throw "";
      }
    }
  } else {
    throw "cannot find version from `forge --verison`, is it installed?";
  }
}

if (!process.env.CI) {
  (async () => {
    try {
      await checkForgeVersion(true); // throw on error
    } catch (e) {
      process.exit(1);
    }
  })();
}
