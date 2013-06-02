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
require "listen"
require "RedCloth"

module RDocView
  def convert(file, type)
    html = ""
    text = open(file){|f|f.read}
    case type
    when "md", "markdown"
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
  
    opt_html = false
    opt_type = nil
    OptionParser.new { |op |
      op.version = VERSION
      op.on('-p port',   'set the port (default is 4567)')           { |val| set :port, Integer(val) }
      op.on('-o addr',   'set the host (default is 0.0.0.0)')        { |val| set :bind, val }
      op.on('-t type',   'set the document type (rdoc,textile,md or markdown)',
                         'if omits, judging from the extension')     { |val| opt_type = val.downcase }
      op.on('-h', '--html', 'convert to html.')                      { |val| opt_html = true }
    }.parse!(ARGV)
    set :environment, :production

    raise "ARGV is empty." if ARGV.empty?
    raise "File Not Found:#{ARGV[0]}" unless File.exists?(ARGV[0])
   
    set :target_file, File.expand_path(ARGV[0])
    set :server, "thin"
    set :sockets, []

    support_extensions = ["rdoc", "md", "markdown", "textile"]
    set :type, opt_type
    set :type, File.extname(ARGV[0]).downcase().slice(1..-1) unless support_extensions.include?(opt_type)

    # HTMLに変換して終了する
    if opt_html then
      html = RDocView.convert(settings.target_file, settings.type)
      html.force_encoding("utf-8")
      tmpl_file = File.expand_path(File.dirname(__FILE__) + "/views/index-html.erb")
      tmpl = ERB.new(open(tmpl_file){|f|f.read})
      puts tmpl.result(binding)
      exit 
    end

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

    # ファイル監視
    callback = Proc.new do |modified, added, removed|
      if modified.include?(settings.target_file) || added.include?(settings.target_file) then
        send_func.call()
      end
    end
    listener = Listen.to(File.dirname(settings.target_file), :relative_paths => false)
      .change(&callback)
      .start

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

