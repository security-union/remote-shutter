# Syncs in-app purchase localizations on App Store Connect to match
# fastlane/iap_localizations.json (creates missing locales, updates changed
# ones). Uses the App Store Connect API directly — deliver does not manage
# IAP metadata. Invoked by the `sync_iap` lane.
require "net/http"
require "json"

module IapSync
  BASE = "https://api.appstoreconnect.apple.com".freeze

  def self.run(bearer_token)
    @bearer = bearer_token
    data = JSON.parse(File.read(File.join(__dir__, "iap_localizations.json")))

    app = req(:get, "/v1/apps?filter[bundleId]=#{data.fetch('bundle_id')}")
      .fetch("data").first or raise "app not found for #{data['bundle_id']}"
    iaps = req(:get, "/v1/apps/#{app['id']}/inAppPurchasesV2?limit=200").fetch("data")

    data.fetch("products").each do |product_id, locales|
      iap = iaps.find { |i| i.dig("attributes", "productId") == product_id }
      unless iap
        puts "SKIP product #{product_id}: not found on App Store Connect"
        next
      end
      existing = req(:get, "/v2/inAppPurchases/#{iap['id']}/inAppPurchaseLocalizations?limit=200")
        .fetch("data")

      locales.each do |locale, strings|
        attrs = { "name" => strings.fetch("name"), "description" => strings.fetch("description") }
        current = existing.find { |l| l.dig("attributes", "locale") == locale }
        if current.nil?
          req(:post, "/v1/inAppPurchaseLocalizations", {
            data: {
              type: "inAppPurchaseLocalizations",
              attributes: attrs.merge("locale" => locale),
              relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap["id"] } } },
            },
          })
          puts "CREATED #{product_id} #{locale}"
        elsif current["attributes"].values_at("name", "description") != attrs.values_at("name", "description")
          req(:patch, "/v1/inAppPurchaseLocalizations/#{current['id']}", {
            data: { type: "inAppPurchaseLocalizations", id: current["id"], attributes: attrs },
          })
          puts "UPDATED #{product_id} #{locale}"
        else
          puts "ok      #{product_id} #{locale}"
        end
      end
    end
  end

  def self.req(method, path, body = nil)
    uri = URI("#{BASE}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
    request = klass.new(uri)
    request["Authorization"] = "Bearer #{@bearer}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json if body
    response = http.request(request)
    unless response.code.to_i < 300
      raise "#{method.upcase} #{path} -> HTTP #{response.code}: #{response.body}"
    end
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  end
end
