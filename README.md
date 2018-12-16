---
labels:
- 'Stage-Alpha'
- 'Type-Auth'
summary: Authentication proxy module for migration
...

Introduction
============

This is a Prosody authentication module which proxies auth requests to multiple authentication backends
and optionally migrates users to the primary one.


Configuration
=============

Copy the module to the prosody modules/plugins directory.

In Prosody's configuration file, under the desired host section, add:

``` {.lua}
authentication = "migrate"
auth_migrate_primary = "sql"
auth_migrate_legacy = { "internal_hashed" }
auth_migrate_migrate = true
```

The available options are:

| Name                   | Description                                               |  Default  |
| ---------------------- | --------------------------------------------------------- | --------- |
| auth\_migrate\_primary | The primary auth backend name where users should reside   |  `nil`    |
| auth\_migrate\_legacy  | List of other existing auth backends                      |  `{}`     |
| auth\_migrate\_migrate | Whether users shall be moved to primary backend on logins |  `true`   |


Description
===========

The purpose of this module is to allow a smooth migration of existing users from one or multiple
existing authentication backends to a new one.

The need to achieve this using a proxy authentication module arises when the existing backends
already use a hashing scheme and the new one uses a different scheme.
In that case, one cannot simply copy the user records from one database to the other since one
requires the actual password to do the rehashing.

The only moment where the cleartext password is and should be available for rehashing is when
the user logs in.

So when a user logs in with username and password, this module will do the following:

- If the user already exists in the primary auth backend, just forward the check to this backend.
- Otherwise search all legacy backends for where the user currently exists. Once found:
  - If authentication with this backend fails, fail entirely.
  - Otherwise create a new user in the primary auth backend with same username and password.
  - And delete the user in the legacy backend if possible.
- If user cannot be found anywhere, fail.

Additionally, whenever the admin (or the user himself) changes a users password and the
user still exists in a legacy backend, then that user will be removed from the lagacy backend
and be recreated in the primary backend using the new password.

Of course new user will always be created in the primary backend.

Over time this will smoothly migrate all your existing users to the new primary authentication backend
without them noticing as long as they log in at some point.


If `auth_migrate_migrate` is disabled, existing users will never be migrated from legacy
auth backends to the primary one.

In that case this module acts more like a fallback chain for multiple userbases.
You could use this e.g. to automatically give your local users accounts in prosody using
`mod_auth_pam` or `mod_auth_ldap` but additionally allow other users or bots to create *prosody-only*
accounts in `mod_auth_internal_hashed`.


Compatiblity
============

Tested with Prosody 0.11.1 on lua 5.2.4.

License
=======

Copyright (c) 2018, Markus Blöchl. Released under the MIT License.

