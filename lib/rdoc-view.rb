# coding: utf-8

$LOAD_PATH.unshift File.dirname(__FILE__)
require "rdoc-view/version"

require "net/https"
require "uri"
require "optparse"
require "rdoc"
require "rdoc/markup/to_html"

require "sinatra/base"
require "sinatra-websocket"
require "fssm"
require "RedCloth"

module RDocView
  def convert(file, type)
    html = ""
    text = open(file){|f|f.read}
    case type
    when "md"
      uri = URI.parse("https://api.github.com/markdown/raw")
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      https.verify_mode = OpenSSL::SSL::VERIFY_NONE
      #https.set_debug_output $stderr
      https.start do | access |
        resp = access.post(uri.path, text, {"content-type" => "text/plain"})
        html = resp.body
      end
    when "textile"
      html = RedCloth.new(text).to_html
    else
      h = RDoc::Markup::ToHtml.new
      html = h.convert(text)
    end
    return html
  end
  module_function :convert

  class ViewApp < Sinatra::Base
   
    opt_type = nil
    OptionParser.new { |op |
      op.on('-p port',   'set the port (default is 4567)')           { |val| set :port, Integer(val) }
      op.on('-o addr',   'set the host (default is 0.0.0.0)')        { |val| set :bind, val }
      op.on('-t type',   'set the document type (rdoc or md or textile)',
                         'if omits, judging from the extension')     { |val| opt_type = val.downcase }
    }.parse!(ARGV)
    set :environment, :production

    raise "ARGV is empty." if ARGV.empty?
    raise "File Not Found:#{ARGV[0]}" unless File.exists?(ARGV[0])
    
    set :target_file, ARGV[0]
    set :server, "thin"
    set :sockets, []

    support_extensions = ["rdoc", "md"]
    set :type, opt_type
    set :type, File.extname(ARGV[0]).downcase().slice(1..-1) unless support_extensions.include?(opt_type)

    send_func = Proc.new do | ws |
      if File.exists?(settings.target_file) then
        # convert to html
        html = RDocView.convert(settings.target_file, settings.type)
        html.force_encoding("utf-8")

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

