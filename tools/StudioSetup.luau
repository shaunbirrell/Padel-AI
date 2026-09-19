--[[
	WAR EMPIRE — StudioSetup (legacy command-bar note)

	Map auto-builds on Play / server start via Server Modules.MapSetup
	when Workspace.WarEmpireSetup is missing. Command-bar paste is no longer required
	(and long pastes truncate in Studio ~488 lines).

	Regenerate map:
	  1. Delete Workspace.WarEmpireSetup (Edit or Play), then Play again, OR
	  2. Admin command: resetmap (Studio; AdminConfig UserIds)

	Optional Play-mode re-run from Command Bar:
	  require(game.ServerScriptService.Server.Modules.MapSetup).Run()
]]

print("[WAR EMPIRE] Auto-setup runs on Play; delete Workspace.WarEmpireSetup and replay to regenerate")
print("[WAR EMPIRE] Or admin resetmap / require(game.ServerScriptService.Server.Modules.MapSetup).Run() in Play")
