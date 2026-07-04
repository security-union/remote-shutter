# Syncs in-app purchase localizations on App Store Connect to match
# fastlane/iap_localizations.json. Uses the App Store Connect API directly —
# deliver does not manage IAP metadata. Invoked by the `sync_iap` lane.
#
# ASC state model: a localization in ACTIVE state (live on the store) is
# immutable — posting a NEW localization for the same locale creates the
# pending edit that goes to review with the next submission. Editable states
# (PREPARE_FOR_SUBMISSION, REJECTED, ...) are patched in place.
require "net/http"
require "json"

module IapSync
  BASE = "https://api.appstoreconnect.apple.com".freeze

  def self.run(bearer_token)
    @bearer = bearer_token
    failures = []
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
        .group_by { |l| l.dig("attributes", "locale") }

      locales.each do |locale, strings|
        attrs = { "name" => strings.fetch("name"), "description" => strings.fetch("description") }
        group = existing[locale] || []
        editable = group.find { |l| %w[PREPARE_FOR_SUBMISSION REJECTED].include?(l.dig("attributes", "state")) }
        target = editable || group.first
        state = target&.dig("attributes", "state")
        begin
          if target && target["attributes"].values_at("name", "description") == attrs.values_at("name", "description")
            puts "ok      #{product_id} #{locale}"
          elsif editable
            req(:patch, "/v1/inAppPurchaseLocalizations/#{editable['id']}", {
              data: { type: "inAppPurchaseLocalizations", id: editable["id"], attributes: attrs },
            })
            puts "UPDATED #{product_id} #{locale}"
          else
            # No editable entry: either the locale is new, or only an immutable
            # ACTIVE entry exists — POST creates the (pending) localization.
            req(:post, "/v1/inAppPurchaseLocalizations", {
              data: {
                type: "inAppPurchaseLocalizations",
                attributes: attrs.merge("locale" => locale),
                relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap["id"] } } },
              },
            })
            puts group.empty? ? "CREATED #{product_id} #{locale}" : "EDITED  #{product_id} #{locale} (pending review)"
          end
        rescue => e
          puts "FAILED  #{product_id} #{locale} (state=#{state}): #{e.message.lines.first&.strip}"
          failures << "#{product_id} #{locale}"
        end
      end
    end
    raise "sync failed for: #{failures.join(', ')}" unless failures.empty?
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
