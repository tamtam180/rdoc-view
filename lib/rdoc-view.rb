# coding: utf-8

$LOAD_PATH.unshift File.dirname(__FILE__)
require "rdoc-view/version"

require "sinatra/base"
require "sinatra-websocket"
require "fssm"
require "rdoc"
require "rdoc/markup/to_html"
require "optparse"

module RDocView
  class ViewApp < Sinatra::Base
    
    OptionParser.new { |op|
      op.on('-p port',   'set the port (default is 4567)')                { |val| set :port, Integer(val) }
      op.on('-o addr',   'set the host (default is 0.0.0.0)')             { |val| set :bind, val }
    }.parse!(ARGV)
    set :environment, :production

    raise "ARGV is empty." if ARGV.empty?
    raise "File Not Found:#{ARGV[0]}" unless File.exists?(ARGV[0])
    
    set :target_file, ARGV[0]
    set :server, "thin"
    set :sockets, []

    send_func = Proc.new do | ws |
      if File.exists?(settings.target_file) then
        text = open(settings.target_file){|f|f.read}
        h = RDoc::Markup::ToHtml.new
        html = h.convert(text)
        
        EM.next_tick do
          if ws then
            ws.send(html)
          else
            settings.sockets.each do |s|
              s.send(html)
            end
          end
        end
      end
    end

    # blockingしちゃうので。
    th = Thread.new(send_func) do | send_func |
      FSSM.monitor(File.dirname(settings.target_file), File.basename(settings.target_file)) do
        update {|b,r| send_func.call()}
        delete {|b,r| }
        create {|b,r| send_func.call()}
      end
    end

    # 簡易的なTimer。定期的にPingを飛ばす。
    th_timer = Thread.new() do
      while true
        EM.next_tick do
          settings.sockets.each do |s|
            s.ping()
          end
        end
        sleep 5
      end
    end

    error 500 do
      "Error: Internal Server Error."
    end

    get "/" do
      erb :index
    end

    get "/rdoc" do
      if request.websocket? then
        request.websocket do | ws |
          ws.onopen do
            settings.sockets << ws
            send_func.call(ws)
          end
          ws.onmessage do | msg |
          end
          ws.onclose do
            settings.sockets.delete(ws)
          end
          ws.onerror do
          end
          ws.onping do
          end
          ws.onpong do
          end
        end
      else
        500
      end
    end
  end
  ViewApp.run! 
end

