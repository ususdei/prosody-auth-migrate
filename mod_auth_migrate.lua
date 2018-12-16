
-- Proxy Authentication Module to aid in migrating users for Prosody IM
-- Copyright (c) 2018 Markus Blöchl
-- Released under the MIT License

local log = module._log
local new_sasl = require "util.sasl".new

local auth_primary    = module:get_option_string("auth_migrate_primary", nil)
local auth_legacy     = module:get_option_array("auth_migrate_legacy", {})
local auth_do_migrate = module:get_option_boolean("auth_migrate_migrate", true)

if auth_primary then module:depends("auth_"..auth_primary) end
for _,a in ipairs(auth_legacy) do module:depends("auth_"..a) end

local auth_providers = {}

for _,a in ipairs(module:get_host_items("auth-provider")) do
    log("debug", "auth-migrate: found auth provider '%s'", a.name)
    auth_providers[a.name] = a
end

local primary = auth_primary and auth_providers[auth_primary]

local provider = {}


function provider.legacy_proxy(method, ...)
    log("debug", "auth-migrate: trying '%s' for all legacy auth methods", method)
    for _,name in ipairs(auth_legacy) do
        if auth_providers[name] and auth_providers[name][method] then
            local rv,err = auth_providers[name][method](...)
            if rv ~= nil then
                log("debug", "legacy auth-provider '%s' handled the call to '%s'", name, method)
                return rv,err
            end
        end
    end
    return nil, method.." failed. No matching auth-provider found."
end


function provider.test_password(username, password)
    if primary then
        local rv,err = primary.test_password(username, password)
        if rv ~= nil then return rv,err end
    end
    local rv,err = provider.legacy_proxy('test_password', username, password)
    if rv == true and auth_do_migrate then provider.set_password(username, password) end
    return rv,err
end

function provider.set_password(username, password)
    if primary and primary.user_exists(username) then
        return primary.set_password(username, password)
    end
    if not auth_do_migrate then
        return provider.legacy_proxy('set_password', username, password)
    end
    for _,name in ipairs(auth_legacy) do
        local legacy = auth_providers[name]
        if legacy and legacy.user_exists(username) then
            local rv,err = primary.create_user(username, password)
            if rv ~= true then return rv,err end
            log("info", "auth-migrate: migrated user '%s' from backend '%s' to '%s'", username, name, auth_primary)
            return legacy.delete_user(username)
        end
    end
    return nil, "user not found"
end

function provider.user_exists(username)
    if primary and primary.user_exists(username) then return true, nil end
    return provider.legacy_proxy('user_exists', username)
end

function provider.is_admin(jid)
    if primary and primary.is_admin and primary.is_admin(jid) then return true, nil end
    return provider.legacy_proxy('is_admin', jid)
end

function provider.users()
    local R = {}
    if primary then
        for user in primary do
            R[#R+1] = user
        end
    end
    for _,name in ipairs(auth_legacy) do
        if auth_providers[name] then
            for user in auth_providers[name].users() do
                R[#R+1] = user
            end
        end
    end
    local i = 0
    local n = #R
    return function() i=i+1 ; if i<=n then return R[i] end end
end

function provider.create_user(username, password)
    if primary then
        return primary.create_user(username, password)
    end
	return nil, "Not primary auth provider."
end

function provider.delete_user(username)
    if primary then
        local rv,err = primary.delete_user(username, password)
        if rv ~= nil then return rv,err end
    end
    return provider.legacy_proxy('delete_user', username)
end

function provider.get_sasl_handler()
	local profile = {
        plain_test = function(_, username, password, realm)
            return provider.test_password(username, password), true
        end
	}
	return new_sasl(module.host, profile)
end

module:provides("auth", provider)

