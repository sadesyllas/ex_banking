# ExBanking

## Notes on the implementation

This application implements the specification layed out
in `INSTRUCTIONS.md`.

It is assumed that since the requirement was for an `:ex_banking`
elixir application, a complete elixir project environment will be
used during testing.

As such, configuration has be placed in `~/config/config.exs` and
the application starts up an `Application` module, namely
`ExBanking.Application` to set up a basic supervision tree.

This is an automatic process so manual calling of a function
external to `ExBanking` is not necessary for the application
to work as described here.,

As such, the requirement that only `ExBanking`
public API functions should be called to test the application
has been honored.

It does not have dependencies and basic tests are run with `mix test`.

For simplicity's sake most of the documentation in the code
points here, so there is not much analysis done in the code files.

The application has been written using
[OTP v20.1](https://github.com/erlang/otp/releases/tag/OTP-20.1) and
[Elixir v1.5.2](https://github.com/elixir-lang/elixir/releases/tag/v1.5.2).

To keep the application `backlog` and the `per user/currency balances`,
[ETS](http://erlang.org/doc/man/ets.html) tables have been used.

Since `ExBanking` is a synchronous API, using
[ETS](http://erlang.org/doc/man/ets.html) tables avoids
all requests going through a single process to keep the relevant data.

## Module `ExBanking`

This module is purely an interface for the rest of the system.
The only logic implemented there is input validation for the data
passed to the rest of the system.

## Module `ExBanking.UserHandler`

The flow is:

1. The public API functions in `ExBanking`, all call into this module
2. This module calls functions in the `ExBanking.UserHandler.Backend`
    module which:
    1. check that the user exists,
    2. handle increasing the backlog for the user handler process,
    3. get the pid for the user handler process and
    4. make the actual `GenServer.call` with the appropriate `pid`
3. When the `GenServer.call` is made with the `pid` of the appropriate
    user handler process, the process delegates once more to data handling
    functions in `ExBanking.UserHandler.Backend`

`GenServer.call` is used instead of `GenServer.cast` to honor
the synchronous nature of the `ExBanking` API.

The first call in `ExBanking.UserHandler.Backend` to fail, short-circuits
the call returning the error to the user.

In a larger application, the concerns of `ExBanking.UserHandler.Backend`
should be split in two parts. One for the handling before `GenServer.call`
and one for the functions used by `GenServer.call`.

#### Optimizing the user handler processes for a long running application

When a user handler process becomes stale, i.e., it has not been used
recently, it is shutdown in a graceful way, which explains why the
[ETS](http://erlang.org/doc/man/ets.html) tables `:user_balances`
and `:user_handlers` are maintained.

As such, if the application runs for a long time, only user processes
actually doing actual work will be running at any given time.

#### [ETS](http://erlang.org/doc/man/ets.html) tables used

The application module, `ExBanking.Application`, sets up 3
[ETS](http://erlang.org/doc/man/ets.html) tables.

1. `:backlog` keeps the created users even if their backlog is `0`
    * actually, this is the mechanism used to initially create a user
    (i.e., no process is started when simply creating users) 
2. `:user_balances` keeps the `per user/currency balances`
3. `:user_handlers` keeps the `pids` of the user handler
    processes currently running

`:user_handlers` keeps both `{user, pid}` and `{pid, user}` entries so
that retrieval can be easily optimized either when knowing the `user` or
the `pid` of the relevant user handler process (please, refer to the
`ExBanking.UserHandler.Watcher` section).

## Module `ExBanking.UserHandler.Backend`

Please, refer to the above `ExBanking.UserHandler` section.

## Module `ExBanking.UserHandler.Watcher`

When a new `ExBanking.UserHandler` process is started, the named
`ExBanking.UserHandler.Watcher` process monitors its `pid`,
through `Process.monitor`, so that if it dies, the relevant entries
in `:user_handlers` can be removed.
