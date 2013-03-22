require 'date'
require 'time'
require 'chef/knife'
require 'chef/knife/core/node_presenter'

class Chef
  class Knife
    class Lastrun < Knife

      deps do
        require 'chef/search/query'
        require 'chef/knife/search'
        require 'chef/node'
      end

      banner "knife lastrun [QUERY] [OPTIONS]"

      option :time,
        :short => "-t",
        :long => "--time",
        :description => "Show failed nodes only"

      option :failed,
        :short => "-f",
        :long => "--failed",
        :description => "Show failed nodes only"

      def header(name, lasttime, status, runtime)
        msg = String.new
        msg << ui.color(name.ljust(40, ' '), :bold)
        msg << ui.color(lasttime.ljust(20, ' '), :bold)
        msg << ui.color(status.ljust(12, ' '), :bold)
        msg << ui.color(runtime.rjust(10, ' '), :bold)
        msg
      end

      def format(name, lasttime, status, runtime)
        case status
        when "Successful"
          color = :green
        when "Failed"
          color = :red
        else
          color = :white
        end

        msg = String.new
        msg << ui.color(name.ljust(40, ' '), :cyan)
        msg << lasttime.ljust(20, ' ')
        msg << ui.color(status.ljust(12, ' '), color)
        msg << runtime.to_s.rjust(10, ' ')
        msg
      end

      def run
        query = @name_args[0].nil? ? "*:*" : @name_args[0]
        nodes = Array.new

        begin
          q = Chef::Search::Query.new
          q.search(:node, query) do |n|
            unless n.automatic_attrs.empty? # filter out bad nodes (clients?)
              begin
                if n.attribute?('cloud')
                  name = n.cloud['public_hostname'].nil? ? n.fqdn : n.cloud['public_hostname']
                else
                  name = n.fqdn
                end
              rescue 
                 ui.error "This should never happen: #{n.name} has no FQDN attribute."
              end

              if n.automatic_attrs.include?('status')
                status = n.automatic['status'].first['status'].to_s
                run_time = n.automatic['status'].first['run_time'].to_i
                last_time = Time.parse(n.automatic['status'].first['start_time']).strftime("%Y-%m-%d %H:%M:%S")
              else
                status = "No status"
                last_time = "Unknown"
                run_time = 0
              end

              unless config[:failed] and status != "Failed"
                nodes << { :name => n.name, :last_time => last_time, :status => status, :run_time => run_time }
              end
            end
          end
        rescue Net::HTTPServerException => e
          msg = Chef::JSONCompat.from_json(e.response_body)["error"].first
          ui.error("knife search failed: #{msg}")
          exit 1
        end

        # Header
        ui.msg "#{nodes.count} items found"
        ui.msg("\n")
        output(header("Name", "Last time", "Status", "Run time"))
        output(header("====", "=========", "======", "========"))

        # Default by name unless -t
        if config[:time]
          nodes.sort_by! { |n| n[:last_time] }.reverse
        else
          nodes.sort_by! { |n| n[:name] }
        end

        nodes.each do |n|
          output(format(n[:name], n[:last_time], n[:status], n[:run_time]))
        end
      end

    end
  end
end
