# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_game_server,
  ecto_repos: [AshGameServer.Repo]

# Configure Ash Framework
config :ash,
  include_embedded_source_in_code?: false

# Configure Spark DSL compilation
config :spark,
  formatter: [
    "Ash.Resource": [
      section_order: [
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"