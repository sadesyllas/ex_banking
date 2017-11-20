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
    3. make the actual money transfer which is also implemented
       in `ExBanking.UserHandler.Backend`

The first call in `ExBanking.UserHandler.Backend` to fail, short-circuits
the call returning the error to the user.

#### [ETS](http://erlang.org/doc/man/ets.html) tables used

The application module, `ExBanking.Application`, sets up 2
[ETS](http://erlang.org/doc/man/ets.html) tables.

1. `:backlog` keeps the created users even if their backlog is `0`
    * actually, this is the mechanism used to initially create a user
    (i.e., no process is started when simply creating users)
2. `:user_balances` keeps the `per user/currency balances`

## Module `ExBanking.UserHandler.Backend`

Please, refer to the above `ExBanking.UserHandler` section.
