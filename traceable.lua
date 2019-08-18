local next = next

local traceable = {}
local _M = traceable

local function merge(dst, src)
    for k, v in next, src do
        dst[k] = v
    end
    return dst
end

local function normalize_field_path(field_path)
    return field_path:gsub("^([-?%d]+)", "[%1]")
                    :gsub("%.([-?%d]+)", "[%1]")
                    :gsub("^([^.%[%]]+)", "['%1']")
                    :gsub("%.([^.%[%]]+)", "['%1']")
end

local getter_template = [[
    return function(t)
        local success, value = pcall(function (t)
            return t%s
        end, t)
        if success then
            return value
        end
    end
]]
local setter_template = [[
    return function(t, v)
        local success, err = pcall(function (t, v)
            t%s = v
        end, t, v)
    end
]]
local getter_cache = {}
local setter_cache = {}
local function compile_normalized_property(field_path)
    local getter, setter = getter_cache[field_path], setter_cache[field_path]
    if not getter then
        getter = assert(loadstring(getter_template:format(field_path)))()
        getter_cache[field_path] = getter
        setter = assert(loadstring(setter_template:format(field_path)))()
        setter_cache[field_path] = setter
    end
    return getter, setter
end

function _M.compile_property(field_path)
    return compile_normalized_property(normalize_field_path(field_path))
end

local set

local function create()
    local o = {
        dirty = false, 
        ignored = false, 
        opaque = false, 

        _stage = {},
        _traced = {},
        _lastversion = {},
        _parent = false, 
    }
    return setmetatable(o, {
        __index = o._stage, 
        __newindex = set,
        
        __len = _M.len, 
        __pairs = _M.pairs, 
        __ipairs = _M.ipairs,
    })
end

local function mark_dirty(t)
    while t and not t.dirty do
        t.dirty = true
        t = t._parent
    end
end

set = function (t, k, v, force)
    local stage = t._stage
    local u = stage[k]
    if _M.is_traceable(v) then
        if _M.is(u) then
            for k in next, u._stage do
                if v[k] == nil then
                    u[k] = nil
                end
            end
        else
            u = create()
            u._parent = t
            stage[k] = u
        end
        merge(u, v)
    else
        local traced = t._traced
        local lastverison = t._lastversion
        if stage[k] ~= v or force then
            if not traced[k] then
                traced[k] = true
                lastverison[k] = u
            end
            stage[k] = v
            mark_dirty(t)
        end
    end
end

function _M.is(t)
    local mt = getmetatable(t)
    return type(mt) == "table" and mt.__newindex == set
end

function _M.is_traceable(t)
    if type(t) ~= "table" then
        return false
    end
    local mt = getmetatable(t)
    return mt == nil or mt.__newindex == set
end

function _M.new(t)
    local o = create()
    if t then
        merge(o, t)
    end
    return o
end

function _M.mark_changed(t, k)
    local v = t[k]
    if _M.is(v) then
        mark_dirty(v)
    else
        set(t, k, v, true)
    end
end

function _M.set_ignored(t, ignored)
    t.ignored = ignored
    if not ignored and t.dirty then
        mark_dirty(t._parent)
    end
end

function _M.set_opaque(t, opaque)
    t.opaque = opaque
end

local k_stub = setmetatable({}, { __tostring = function () return "k_stub" end })
function _M.compile_map(src)
    local o = {}
    for i = 1, #src do
        local v = src[i]
        local argc = #v
        -- v = {argc, action, arg1, arg2, ..., argn}
        v = {argc, unpack(v)} -- copy

        for j = 1, argc - 1 do
            local k = j + 2
            local arg = normalize_field_path(v[k])
            v[k] = compile_normalized_property(arg)
            local p, c = nil, o
            for field in arg:gmatch("([^%[%]\'\"]+)") do
                field = tonumber(field) or field
                p, c = c, c[field]
                if not c then
                    c = {}
                    p[field] = c
                end
            end
            local stub = c[k_stub]
            if not stub then
                stub = {[1] = 1}
                c[k_stub] = stub
            end
            local n = stub[1] + 1
            stub[1] = n
            stub[n] = v
        end
    end
    return o
end

local function get_map_stub(map, k)
    local map_k = map[k]
    return map_k and map_k[k_stub]
end

local argv = {}
local function do_map(t, mappings, mapped)
    for i = 2, mappings[1] do
        local mapping = mappings[i]
        if not mapped[mapping] then
            mapped[mapping] = true
            local argc = mapping[1]
            argv[1] = t
            for i = 2, argc do
                argv[i] = mapping[i + 1](t)
            end
            
            local action = mapping[2]
            action(unpack(argv, 1, argc))
        end
    end
end

local function next_traced(t, k)
    local k = next(t._traced, k)
    return k, t._stage[k], t._lastversion[k]
end

local function diff(t, sub, changed, newestversion, lastversion, map, mapped)
    if not sub.dirty then
        return false
    end

    local has_changed = next(sub._traced) ~= nil
    for k, v in next, sub._stage do
        if _M.is(v) and not v.ignored then
            if v.opaque then
                has_changed = diff(t, v)
                if has_changed then
                    if changed then
                        changed[k] = true
                    end
                end
            else
                local c, n, l = changed and {}, newestversion and {}, lastversion and {}
                has_changed = diff(t, v, c, n, l, map and map[k], mapped)
                if has_changed then
                    if changed then
                        changed[k] = c
                    end
                    if newestversion then
                        newestversion[k] = n
                    end                
                    if lastversion then
                        lastversion[k] = l
                    end
                end
            end

            if has_changed and map then
                local stub = get_map_stub(map, k)
                if stub then
                    do_map(t, stub, mapped)
                end
            end
        end
    end

    for k, v, u in next_traced, sub do
        if changed then
            changed[k] = true
        end

        if newestversion then
            newestversion[k] = v
        end
        if lastversion then
            lastversion[k] = u
        end

        if map then
            local stub = get_map_stub(map, k)
            if stub then
                do_map(t, stub, mapped)
            end
        end
    end

    return has_changed, changed, newestversion, lastversion
end

function _M.diff(t, changed, newestversion, lastversion, map)
    if changed ~= nil and newestversion == nil and lastversion == nil and map == nil then
        changed, newestversion, lastversion, map = nil, nil, nil, changed
    end
    
    local has_changed = diff(t, t, changed, newestversion, lastversion, map, map and {})
    return has_changed, changed, newestversion, lastversion
end

local function commit(t, sub, map, mapped)
    if not sub.dirty then
        return false
    end
    
    local traced = sub._traced
    local lastverison = sub._lastversion

    local committed = next(traced) ~= nil
    for k, v in next, sub._stage do
        if _M.is(v) and not v.ignored then
            if v.opaque then
                committed = commit(t, v)
            else
                committed = commit(t, v, map and map[k], mapped)
            end
            if committed and map then
                local stub = get_map_stub(map, k)
                if stub then
                    do_map(t, stub, mapped)
                end
            end
        end
    end

    for k in next, traced do
        traced[k] = nil
        lastverison[k] = nil
        
        if map then
            local stub = get_map_stub(map, k)
            if stub then
                do_map(t, stub, mapped)
            end
        end
    end

    sub.dirty = false
    return committed
end

function _M.commit(t, map)
    commit(t, t, map, map and {})
end

local function do_maps(t, sub, map, mapped)
    for k, map_k in next, map do
        local stub = map_k[k_stub]
        if stub then
            do_map(t, stub, mapped) 
        end
        
        local v = sub[k]
        if type(v) == "table" then
            do_maps(t, v, map_k, mapped)
        end
    end
end

function _M.map(t, map)
    do_maps(t, t, map, map and {})
end

local function forward_to(field, func)
    return function (t, ...)
        return func(t[field], ...)
    end
end


function _M.len(t)
    return #(t._stage)
end
_M.next = forward_to("_stage", next)
_M.pairs = forward_to("_stage", pairs)
_M.ipairs = forward_to("_stage", ipairs)
_M.unpack = forward_to("_stage", unpack)

return _M