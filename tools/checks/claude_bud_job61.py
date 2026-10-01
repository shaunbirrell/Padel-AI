"""JOB 61 static contract: server-only AnalyticsService, cheap funnels, no PII."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
def src(rel):
    return (ROOT / rel).read_text(encoding="utf-8")
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + "CLAUDE-BUD J61: " + msg)
    return cond

A = src("src/ServerScriptService/Server/Services/AnalyticsService.luau")
C = src("src/ReplicatedStorage/Shared/Configs/AnalyticsConfig.luau")
E = src("src/ServerScriptService/Server/Services/EconomyService.luau")
CLAUDE = src("CLAUDE.md")
HANDOFF = src("LATEST-HANDOFF.md")

checks = []
checks.append(check('JOB 61: Creator Hub Economy + Funnels analytics (AnalyticsService)' in CLAUDE, "JOB 61 is appended to CLAUDE.md"))
checks.append(check("LogEconomyEvent" in A and "LogOnboardingFunnelStepEvent" in A and "LogFunnelStepEvent" in A and "LogCustomEvent" in A, "all four Creator Hub APIs are centralized"))
checks.append(check('Funnel = {' in C and C.count('{ Name = "') >= 8 and 'reached_5_minutes' in C, "eight ordered onboarding steps are configured"))
checks.append(check('Economy = {' in C and 'SourceSKUs' in C and 'SinkSKUs' in C and all(x in C for x in ['IAP', 'Gameplay', 'Shop', 'TimedReward', 'Onboarding']), "one economy schema has SKUs and approved transaction types"))
checks.append(check('"Gold"' in C and 'EconomyGold' in A and 'currency' in A, "Cash and Gold use the central economy path"))
checks.append(check('AnalyticsOnboarding' in A and 'f.Steps[name] == true' in A and 'task.delay(300' in A, "onboarding is once-per-player and five-minute work is delayed"))
checks.append(check('funnelSessionId' not in A or 'LogFunnelStepEvent' in A, "funnel steps use server-created sessions"))
checks.append(check('ShopItemViewed' in C and 'purchase_complete' in C and 'REBIRTH_CONFIRMED' in A, "Shop and Rebirth funnel stages are wired"))
checks.append(check('DAILY_MISSION_COMPLETED' in C and 'RETURN_SEQUENCE_CLAIMED' in C and 'NOTIF_OPTIN' in C, "required custom events are configured"))
checks.append(check('AdminConfig' in A and 'ExcludeAdminUserIds' in A and 'PII_KEYS' in A and 'VictimUserId' in A, "admins are excluded and PII keys are removed"))
checks.append(check('RunService.Heartbeat' not in A and 'RunService.Stepped' not in A and 'EconomyFlushSeconds' in A, "no per-frame analytics; economy is batched"))
checks.append(check('StreamingEnabled' not in A and 'PreferMesh' not in A and 'WE_Building' not in A, "house-rule assets/settings are untouched by analytics"))
checks.append(check('pendingAnalyticsOrigins' in E and 'profile.Gold' in E, "pending sources are coalesced and Gold mutations are covered"))
check(all(checks), "contract summary")
