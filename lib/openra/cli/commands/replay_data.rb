require 'json'

module Openra
  class CLI
    module Commands
      class ReplayData < Hanami::CLI::Command
        desc 'Output replay data to stdout'

        argument :replay, required: true, desc: 'Path of the replay file to read data from'
        option :format, default: 'json', values: %w(json pretty-json), desc: 'Output format'

        def call(replay:, **options)
          replay = Openra::Replays::Replay.new(replay)

          players = replay.metadata.each_with_object([]) do |(key, value), arr|
            next unless key.start_with?('Player')
            arr << value
          end
          player_indices = players.map { |player| player['ClientIndex'] }
          player_teams = players.map { |player| player['Team'] }
          team_alignment = player_teams.each_with_object({}) do |team, hash|
            if team == 0
              hash[SecureRandom.uuid] = 1
            else
              hash[team] ||= 0
              hash[team] += 1
            end
          end

          replay_data = {
            mod: replay.mod,
            version: replay.version,
            server_name: nil,
            map: {
              name: utf8(replay.map_title),
              hash: replay.map_id
            },
            game: {
              type: team_alignment.values.join('v'),
              start_time: replay.start_time,
              end_time: replay.end_time,
              duration: replay.duration,
              options: {}
            },
            clients: [],
            chat: []
          }

          timestep = nil
          sync_info_orders = replay.orders.select do |order|
            order.command == 'SyncInfo'
          end
          num_sync_info_orders = sync_info_orders.length

          sync_info_orders.each.with_index do |sync_info_order, index|
            sync_info = Openra::YAML.load(sync_info_order.target)

            # Get all clients
            sync_info.each_pair do |key, data|
              case key
              when /^Client@/
                replay_data[:clients] << {
                  index: data['Index'],
                  name: utf8(data['Name']),
                  preferred_color: data['PreferredColor'],
                  color: data['Color'],
                  faction: data['Faction'],
                  ip: data['IpAddress'],
                  team: data['Team'] == 0 ? nil : data['Team'],
                  is_bot: data['Bot'].nil? ? false : true,
                  is_admin: data['IsAdmin'] == 'True',
                  is_player: player_indices.include?(data['Index']),
                  build: []
                }
              when 'GlobalSettings'
                next unless index.next == num_sync_info_orders

                timestep = data['Timestep']
                replay_data[:server_name] = data['ServerName']
                replay_data[:game][:options] = {
                  explored_map: data['Options']['explored']['Value'] == 'True',
                  speed: data['Options']['gamespeed']['Value'],
                  starting_cash: data['Options']['startingcash']['Value'],
                  starting_units: data['Options']['startingunits']['Value'],
                  fog_enabled: data['Options']['fog']['Value'] == 'True',
                  cheats_enabled: data['Options']['cheats']['Value'] == 'True',
                  kill_bounty_enabled: data['Options']['bounty']['Value'] == 'True',
                  allow_undeploy: data['Options']['factundeploy']['Value'] == 'True',
                  crated_enabled: data['Options']['crates']['Value'] == 'True',
                  build_off_allies: data['Options']['allybuild']['Value'] == 'True',
                  restrict_build_radius: data['Options']['buildradius']['Value'] == 'True',
                  short_game: data['Options']['shortgame']['Value'] == 'True',
                  techlevel: data['Options']['techlevel']['Value']
                }
              end
            end
          end

          replay.orders.each do |order|
            case order.command
            when 'PlaceBuilding'
              client = replay_data[:clients].find do |candidate|
                candidate[:index] == order.client_index.to_s
              end

              client[:build] << {
                structure: order.target_string,
                placement: {
                  x: order.target_x,
                  y: order.target_y
                }
              }
            when 'Chat'
              client = replay_data[:clients].find do |candidate|
                candidate[:index] == order.client_index.to_s
              end

              replay_data[:chat] << {
                name: client[:name],
                message: utf8(order.target)
              }
            end
          end

          case options[:format]
          when 'json'
            puts JSON.dump(replay_data)
          when 'pretty-json'
            puts JSON.pretty_generate(replay_data)
          end
        end

        private

        def utf8(string)
          string.force_encoding('UTF-8')
        end
      end
    end
  end
end
