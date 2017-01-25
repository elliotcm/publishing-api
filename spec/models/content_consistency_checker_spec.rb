require "rails_helper"

RSpec.describe ContentConsistencyChecker do
  describe "#call" do
    describe "invalid content ID" do
      subject { described_class.new("invalid content ID").call }

      it "should have errors" do
        expect(subject).not_to be_empty
      end
    end

    describe "valid content" do
      let(:item) { FactoryGirl.create(:content_item) }

      subject { described_class.new(item.content_id).call }

      it "should not have errors" do
        stub_request(:get, "http://draft-content-store.dev.gov.uk/content#{item.base_path}").
             with(:headers => {'Accept'=>'application/json', 'Accept-Encoding'=>'gzip, deflate', 'Host'=>'draft-content-store.dev.gov.uk', 'User-Agent'=>'gds-api-adapters/38.1.0 ()'}).
             to_return(:status => 200, :body => '{"analytics_identifier":null,"base_path":"/","content_id":"f3bbdec2-0e62-4520-a7fd-6ffd5d36e03a","document_type":"special_route","first_published_at":"2016-02-29T09:24:10.000+00:00","format":"special_route","locale":"en","need_ids":[],"phase":"live","public_updated_at":"2017-01-19T12:10:45.000+00:00","publishing_app":"frontend","rendering_app":"frontend","schema_name":"special_route","title":"GOV.UK homepage","updated_at":"2017-01-19T12:10:45.560Z","withdrawn_notice":{},"links":{"available_translations":[{"analytics_identifier":null,"content_id":"f3bbdec2-0e62-4520-a7fd-6ffd5d36e03a","description":"","document_type":"special_route","public_updated_at":"2017-01-19T12:10:45Z","schema_name":"special_route","title":"GOV.UK homepage","base_path":"/","locale":"en","api_path":"/api/content/","withdrawn":false,"api_url":"http://www.dev.gov.uk/api/content/","web_url":"http://www.dev.gov.uk/","links":{}}]},"description":"","details":{}}', :headers => {"Content-Type": "application/json; charset=utf-8"})

        expect(subject).to be_empty
      end
    end

    context "has redirects" do
      let(:item) do
        FactoryGirl.create(:redirect_content_item)
      end

      subject { described_class.new(item.content_id).call }

      context "router API does not have an entry for the item" do
        before do
          stub_request(:get, "http://router-api.dev.gov.uk/routes?incoming_path=#{item.base_path}").
            and_return(:status => 404)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/not found/)
        end
      end

      context "router API handler is not marked as a redirect" do
        before do
          stub_router({
            backend_id: "frontend",
            disabled: "false",
            handler: "backend",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/Handler is not a redirect for/)
        end
      end

      context "router API redirect destination does not match" do
        before do
          stub_router({
            backend_id: "frontend",
            disabled: "false",
            handler: "redirect",
            incoming_path: item.base_path,
            route_type: "exact",
            redirect_to: "/somewhere-else"
          }, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/does not match item destination/)
        end
      end
    end

    context "has routes" do
      let(:item) do
        FactoryGirl.create(:live_content_item)
      end

      subject { described_class.new(item.content_id).call }

      context "router API does not have an entry for the item" do
        before do
          stub_request(:get, "http://router-api.dev.gov.uk/routes?incoming_path=#{item.base_path}").
            and_return(:status => 404)
          stub_content_store("live", {}, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/not found/)
        end
      end

      context "router API does not have an entry for the item" do
        before do
          stub_router({
            backend_id: "falafel",
            disabled: false,
            handler: "backend",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)

          stub_content_store("live", {}, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/does not match item backend/)
        end
      end

      context "router API has item marked as disabled" do
        before do
          stub_router({
            backend_id: "frontend",
            disabled: true,
            handler: "backend",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)

          stub_content_store("live", {}, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/is marked as disabled/)
        end
      end

      context "router API has a different handler" do
        before do
          stub_router({
            backend_id: "frontend",
            disabled: false,
            handler: "redirect",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)

          stub_content_store("live", {}, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/does not match expected item handler/)
        end
      end

      context "router API has a different handler for a gone item" do
        let(:item) { FactoryGirl.create(:gone_content_item) }
        before do
          stub_router({
            disabled: false,
            handler: "backend",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)

          stub_content_store("draft", {}, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/does not match expected item handler/)
        end
      end

      context "item is gone but exists in the content store" do
        let(:item) { FactoryGirl.create(:gone_content_item) }
        before do
          stub_router({
            disabled: false,
            handler: "gone",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)

          stub_content_store("draft", {}, item.base_path)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/the content exists in a content store/)
        end
      end

      context "item is published but not in the content store" do
        let(:item) { FactoryGirl.create(:live_content_item) }
        before do
          stub_router({
            backend_id: "frontend",
            disabled: false,
            handler: "backend",
            incoming_path: item.base_path,
            route_type: "exact",
          }, item.base_path)

          stub_content_store("live", {}, item.base_path, 404)
        end

        it "should produce an error" do
          expect(subject).not_to be_empty
          expect(subject.first).to match(/content is not in live content store/)
        end
      end
    end
  end
end

def router_api_url
  Plek.find('router-api')
end

def content_store_url(instance)
  prefix = instance == "draft" ? "draft-" : ""
  Plek.find("#{prefix}content-store")
end

def stub_router(body, path="/test-redirect")
  stub_request(:get, "#{router_api_url}/routes?incoming_path=#{path}").
    and_return(:status => 200, :body => body.to_json, :headers => {"Content-Type": "application/json"})
end

def stub_content_store(instance, body, path, status = 200)
  stub_request(:get, "#{content_store_url(instance)}/content#{path}").
    and_return(:status => status, :body => body.to_json, :headers => {})
end
