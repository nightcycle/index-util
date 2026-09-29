--!strict
-- Services
-- Packages
local TypeUnionLib = require(script.Parent.TypeUnionLib)
local Future = TypeUnionLib.Future
local Result = TypeUnionLib.Result
-- Modules
-- Types
export type ToDo<V, Progress...> = TypeUnionLib.ToDo<V, Progress...>
export type Result<V, E> = TypeUnionLib.Result<V, E>
-- Constants
local INF_WARN_AT = 20
local DEFAULT_SEPARATOR = "/"
local GLOBAL_FIRST_KEYS = { "src", "game", ".", "", "@game" }
-- Variables
-- References
-- Private Functions
local function errMessage(
	reason: string,
	path: string,
	root: Instance?,
	separator: string?,
	filteredInitialKeys: { string }?
): string
	return `{reason} at `
		.. (if root then `local path "{path}" for {root:GetFullName()}` else `global path "{path}"`)
		.. (if separator then ` with separator "{separator}"` else "")
		.. (if filteredInitialKeys then ` using filtered keys [{table.concat(filteredInitialKeys, ",")}]` else "")
end
local function yieldUntil<V>(
	fn: () -> V?,
	duration: number?,
	warnMsg: string,
	isSilent: boolean?,
	getIfCanceled: (() -> boolean)?
): V?
	local v = fn()
	do
		local start = tick()
		local didWarn = false
		while v == nil do
			local elapsedT = tick() - start
			if getIfCanceled and getIfCanceled() then
				break
			end
			if duration and elapsedT > duration then
				break
			elseif elapsedT > INF_WARN_AT then
				if not didWarn and not isSilent then
					didWarn = true
					warn(warnMsg)
				end
			end
			task.wait()
			v = fn()
		end
	end
	return v
end
local function findFirstMatch<V>(inst: Instance, process: (desc: Instance) -> V?, recursive: boolean?): V?
	if recursive then
		for i, v in ipairs(inst:GetDescendants()) do
			local result = process(v)
			if result ~= nil then
				return result
			end
		end
	else
		for i, v in ipairs(inst:GetChildren()) do
			local result = process(v)
			if result ~= nil then
				return result
			end
		end
	end
	return nil
end
local function waitForMatchWithCancel<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	yield: number?,
	recursive: boolean?,
	isSilent: boolean?,
	getIfCanceled: (() -> boolean)?
): V?
	local isAlive = true
	local deathConnection: RBXScriptConnection
	local onAdded: RBXScriptConnection

	local cleanUp = function(): ()
		if not isAlive then
			return
		end
		isAlive = false
		deathConnection:Disconnect()
		onAdded:Disconnect()
	end
	local isDead = false
	deathConnection = inst.Destroying:Connect(function()
		isDead = true
		cleanUp()
	end)

	local match: V?
	local processError: string?
	local onNewChild = function(descendant: Instance)
		if not isAlive or match ~= nil then
			return
		end
		local success, potentialMatch = pcall(process, descendant)
		if not success then
			processError = tostring(potentialMatch)
			cleanUp()
		elseif isAlive and match == nil and potentialMatch ~= nil then
			match = potentialMatch
		end
	end

	if recursive then
		onAdded = inst.DescendantAdded:Connect(onNewChild)
	else
		onAdded = inst.ChildAdded:Connect(onNewChild)
	end

	local outRes: Result<V, nil>?
	local success, message = pcall(function()
		local initialMatch = findFirstMatch(inst, process, recursive)
		if match == nil then
			match = initialMatch
		end
		outRes = yieldUntil(
			function(): Result<V, nil>?
				if processError ~= nil then
					error(processError, 0)
				elseif isDead or (getIfCanceled and getIfCanceled()) then
					return Result.err(nil)
				elseif match ~= nil then
					return Result.ok(match)
				end
				return nil
			end,
			yield,
			`Infinite yield possible on waitForMatch({inst:GetFullName()}, recursive={recursive == true})`,
			isSilent
		)
	end)
	cleanUp()
	if not success then
		error(message, 0)
	end
	if getIfCanceled and getIfCanceled() then
		return nil
	end
	if outRes then
		if outRes.IsOk then
			return outRes.Value
		elseif not yield then
			error(`Instance {inst:GetFullName()} was destroyed before match found`)
		else
			return nil
		end
	else
		return nil
	end
end
local function findFirstLocalPath(
	root: Instance,
	path: string,
	separator: string?,
	filteredInitialKeys: { string }?
): Instance?
	local keys = string.split(path, separator or DEFAULT_SEPARATOR)
	if filteredInitialKeys then
		for i, v in filteredInitialKeys do
			if keys[1] == v then
				table.remove(keys, 1)
				break
			end
		end
	end
	local source: Instance = root
	local function index(i: number): Instance?
		local key = keys[i]
		if not key then
			return source :: any
		end

		local child = source:FindFirstChild(key)
		if not child then
			return nil
		end
		assert(child)
		source = child
		return index(i + 1)
	end
	return index(1)
end
local function waitForLocalPathWithCancel(
	root: Instance,
	path: string,
	duration: number?,
	separator: string?,
	filteredInitialKeys: { string }?,
	isSilent: boolean?,
	getIfCanceled: (() -> boolean)?
): Instance?
	return yieldUntil(function()
		return findFirstLocalPath(root, path, separator, filteredInitialKeys)
	end, duration, errMessage(`Infinite yield possible`, path, nil, separator), isSilent, getIfCanceled)
end
-- Class
local Util = {}

function Util.findFirstLocalPath(
	root: Instance,
	path: string,
	separator: string?,
	filteredInitialKeys: { string }?
): Instance?
	return findFirstLocalPath(root, path, separator, filteredInitialKeys)
end

function Util.tryFirstLocalPath(
	root: Instance,
	path: string,
	separator: string?,
	filteredInitialKeys: { string }?
): Result<Instance, string>
	local hit = Util.findFirstLocalPath(root, path, separator, filteredInitialKeys)
	if hit == nil then
		return Result.err(errMessage(`No instance found`, path, root, separator, filteredInitialKeys))
	else
		return Result.ok(hit)
	end
end

function Util.findFirstPath(path: string, separator: string?): Instance?
	return Util.findFirstLocalPath(game, path, separator, GLOBAL_FIRST_KEYS)
end

function Util.tryFirstPath(path: string, separator: string?): Result<Instance, string>
	local hit = Util.findFirstPath(path, separator)
	if hit == nil then
		return Result.err(errMessage(`No instance found`, path, nil, separator))
	else
		return Result.ok(hit)
	end
end

Util.waitForLocalPath = function(
	root: Instance,
	path: string,
	duration: number?,
	separator: string?,
	filteredInitialKeys: { string }?,
	isSilent: boolean?
): Instance?
	return yieldUntil(function()
		return Util.findFirstLocalPath(root, path, separator, filteredInitialKeys)
	end, duration, errMessage(`Infinite yield possible`, path, nil, separator), isSilent)
end :: ((
	root: Instance,
	path: string,
	duration: nil,
	separator: string?,
	filteredInitialKeys: { string }?,
	isSilent: boolean?
) -> Instance) & ((
	root: Instance,
	path: string,
	duration: number,
	separator: string?,
	filteredInitialKeys: { string }?,
	isSilent: boolean?
) -> Instance?)

Util.getFutureLocalPath = function(
	root: Instance,
	path: string,
	separator: string?,
	filteredInitialKeys: { string }?
): ToDo<Instance>
	return Future.toDo(function(complete: (Instance) -> (), getIfCancelled: () -> boolean)
		local hit = waitForLocalPathWithCancel(root, path, nil, separator, filteredInitialKeys, true, getIfCancelled)
		if getIfCancelled() then
			return
		end
		assert(hit, `hit shouldn't be null`)
		complete(hit)
	end)
end

Util.waitForPath = function(path: string, duration: number?, separator: string?, isSilent: boolean?): any
	return Util.waitForLocalPath(game, path, duration :: nil, separator, GLOBAL_FIRST_KEYS, isSilent)
end :: ((path: string, duration: nil, separator: string?, isSilent: boolean?) -> Instance) & ((path: string, duration: number, separator: string?, isSilent: boolean?) -> Instance?)

Util.getFuturePath = function(path: string, separator: string?): ToDo<Instance>
	return Util.getFutureLocalPath(game, path, separator, GLOBAL_FIRST_KEYS)
end

function Util.findFirstMatch<V>(inst: Instance, process: (desc: Instance) -> V?, recursive: boolean?): V?
	return findFirstMatch(inst, process, recursive)
end

function Util.tryFirstMatch<V>(inst: Instance, process: (desc: Instance) -> V?, recursive: boolean?): Result<V, string>
	local hit = Util.findFirstMatch(inst, process, recursive)
	if hit == nil then
		return Result.err(
			`No matches found within {recursive == true and "descendants" or "children"} of {inst:GetFullName()}`
		)
	else
		return Result.ok(hit)
	end
end

Util.waitForMatch = function<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	yield: number?,
	recursive: boolean?,
	isSilent: boolean?
): any
	return waitForMatchWithCancel(inst, process, yield, recursive, isSilent)
end :: (<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	yield: nil,
	recursive: boolean?,
	isSilent: boolean?
) -> V) & (<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	yield: number,
	recursive: boolean?,
	isSilent: boolean?
) -> V?)

Util.getFutureMatch = function<V>(
	inst: Instance,
	process: (desc: Instance) -> V?,
	recursive: boolean?
): ToDo<Result<V, string>>
	return Future.toDo(function(complete: (Result<V, string>) -> (), getIfCancelled)
		local hit: V?
		local success, msg = pcall(function()
			hit = waitForMatchWithCancel(inst, process, nil, recursive, true, getIfCancelled)
		end)
		if getIfCancelled() then
			return
		end
		if not success then
			complete(Result.err(tostring(msg)))
		else
			assert(hit ~= nil, `hit should have been assigned`)
			complete(Result.ok(hit))
		end
	end)
end

return Util
