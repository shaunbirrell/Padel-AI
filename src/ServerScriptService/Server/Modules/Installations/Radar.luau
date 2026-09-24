--!strict
--[[
	Radar installation (HollowBuildingBuilder, StructureVisualConfig.Installations). 24 x 20: control hut,
	lattice tower with a rotating dish (client-side spin via api.spin), cable trench. Kiosk outside the front.
	L1 hut + 10-stud tower + small dish   L2 taller tower, generator   L3 big dish + platform railing
	L4 phased-array panel on the hut      L5 radome on its own tower, gold trim
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local white = Color3.fromRGB(222, 224, 218)

	-- L5 gold edge band around a roof (matches the walk-in buildings' gold parapet cap)
	local function goldEdge(cx: number, y: number, cz: number, w: number, d: number)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz + d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz - d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx + w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx - w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
	end

	local function beam(name: string, a: Vector3, b: Vector3, thick: number, color: Color3)
		local mid = (a + b) * 0.5
		api.part(name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt(mid, b), color, Enum.Material.Metal, false)
	end

	-- Lattice tower: 4 legs, X-braces every 4 studs, a platform on top. Returns the platform top Y.
	local function tower(tx: number, tz: number, h: number, half: number): number
		for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			api.box("TowerLeg", Vector3.new(0.4, h, 0.4), Vector3.new(tx + o[1] * half, y0 + h * 0.5, tz + o[2] * half), col.Metal, Enum.Material.Metal)
		end
		local steps = math.max(1, math.floor(h / 4))
		for k = 0, steps - 1 do
			local ya, yb = y0 + k * (h / steps), y0 + (k + 1) * (h / steps)
			beam("TowerBrace", Vector3.new(tx - half, ya, tz + half), Vector3.new(tx + half, yb, tz + half), 0.2, col.Metal)
			beam("TowerBrace", Vector3.new(tx + half, ya, tz - half), Vector3.new(tx - half, yb, tz - half), 0.2, col.Metal)
			beam("TowerBrace", Vector3.new(tx - half, ya, tz - half), Vector3.new(tx - half, yb, tz + half), 0.2, col.Metal)
			beam("TowerBrace", Vector3.new(tx + half, ya, tz + half), Vector3.new(tx + half, yb, tz - half), 0.2, col.Metal)
		end
		api.box("TowerPlatform", Vector3.new(half * 2 + 1.6, 0.4, half * 2 + 1.6), Vector3.new(tx, y0 + h + 0.2, tz), col.Metal, Enum.Material.DiamondPlate)
		return y0 + h + 0.4
	end

	-- Control hut (front-left)
	local hx, hz, hW, hD, hH = -6, 3, 9, 8, 6.5
	api.box("RadarHut", Vector3.new(hW, hH, hD), Vector3.new(hx, y0 + hH * 0.5, hz), col.Wall, Enum.Material.Concrete)
	api.box("RadarHutRoof", Vector3.new(hW + 0.6, 0.5, hD + 0.6), Vector3.new(hx, y0 + hH + 0.25, hz), col.Trim, Enum.Material.Metal)
	if lv >= 5 then
		goldEdge(hx, y0 + hH + 0.65, hz, hW + 0.6, hD + 0.6)
	end
	api.box("RadarHutDoor", Vector3.new(2.6, 5, 0.2), Vector3.new(hx + 2.4, y0 + 2.5, hz + hD * 0.5 + 0.1), col.Metal, Enum.Material.Metal, false)
	local win = api.box("RadarHutWindow", Vector3.new(3.2, 1.6, 0.2), Vector3.new(hx - 1.8, y0 + 3.8, hz + hD * 0.5 + 0.1), col.Glass, Enum.Material.Glass, false)
	win.Transparency = 0.3
	local sign = api.box("RadarSign", Vector3.new(6, 1.1, 0.2), Vector3.new(hx, y0 + hH - 0.9, hz + hD * 0.5 + 0.12), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(sign, Enum.NormalId.Back, { "RADAR CONTROL" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	api.box("HutAC", Vector3.new(2.2, 1.4, 1.6), Vector3.new(hx - 2.5, y0 + hH + 1.2, hz - 1.5), col.Metal, Enum.Material.DiamondPlate)

	-- Main tower + dish (back-right)
	local tx, tz = 5, -3
	local h = ({ 10, 13, 15, 16, 17 })[lv] or 10
	local top = tower(tx, tz, h, 1.5)
	if lv >= 3 then
		for _, side in ipairs({ -1, 1 }) do
			api.box("PlatformRail", Vector3.new(4.6, 0.2, 0.2), Vector3.new(tx, top + 1.1, tz + side * 2.2), col.Accent, Enum.Material.Metal, false)
			api.box("PlatformRail", Vector3.new(0.2, 0.2, 4.6), Vector3.new(tx + side * 2.2, top + 1.1, tz), col.Accent, Enum.Material.Metal, false)
		end
	end
	local dishD = if lv >= 3 then 8 else 5
	api.cylinder("DishMast", Vector3.new(2, 0.7, 0.7), CFrame.new(tx, top + 1, tz) * CFrame.Angles(0, 0, math.rad(90)), col.Dark, Enum.Material.Metal)
	local dish = api.cylinder("RadarDish", Vector3.new(0.4, dishD, dishD), CFrame.new(tx, top + 2 + dishD * 0.35, tz - 0.6) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(20)), white, Enum.Material.SmoothPlastic, false)
	local feedArm = api.part("FeedArm", Vector3.new(0.2, 0.2, 2.6), CFrame.new(tx, top + 2 + dishD * 0.35, tz + 0.7), col.Metal, Enum.Material.Metal, false)
	local feed = api.ball("FeedHorn", 0.6, Vector3.new(tx, top + 2 + dishD * 0.35, tz + 2), col.Dark, Enum.Material.Metal, false)
	api.spin({ dish, feedArm, feed }, Vector3.new(tx, 0, tz), if lv >= 3 then 8 else 12)

	-- Cable trench hut → tower
	api.box("CableTrench", Vector3.new(0.8, 0.1, 7), Vector3.new(0.5, y0 + 0.05, 0.5), col.Dark, Enum.Material.Metal, false)

	-- Generator (L2+)
	if lv >= 2 then
		api.box("Generator", Vector3.new(3.4, 2.2, 2), Vector3.new(-8.5, y0 + 1.1, -6), col.Locker, Enum.Material.DiamondPlate)
		api.box("GeneratorStripe", Vector3.new(3.45, 0.4, 2.05), Vector3.new(-8.5, y0 + 1.7, -6), col.Accent, Enum.Material.SmoothPlastic, false)
	end

	-- Phased-array panel on the hut roof (L4+)
	if lv >= 4 then
		api.part("PhasedArray", Vector3.new(5, 3.6, 0.5), CFrame.new(hx + 1, y0 + hH + 2.4, hz - 1) * CFrame.Angles(math.rad(-20), 0, 0), col.Dark, Enum.Material.Metal)
		for i = -1, 1 do
			api.box("ArrayLed", Vector3.new(0.3, 0.3, 0.1), Vector3.new(hx + 1 + i * 1.2, y0 + hH + 1.4, hz - 0.45), col.Screen, Enum.Material.Neon, false)
		end
	end

	-- Radome on a short tower (L5)
	if lv >= 5 then
		local rtop = tower(-6, -6, 6, 1.4)
		api.ball("Radome", 6.5, Vector3.new(-6, rtop + 3, -6), white, Enum.Material.SmoothPlastic)
	end

	-- Warning lamp on the main tower
	local lamp = api.ball("TowerLamp", 0.6, Vector3.new(tx + 1.5, top + 0.5, tz + 1.5), Color3.fromRGB(255, 50, 40), Enum.Material.Neon, false)
	api.light(lamp, 8, 1.2, Color3.fromRGB(255, 60, 40))
end
