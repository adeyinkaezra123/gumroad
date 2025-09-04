# frozen_string_literal: true

require "spec_helper"

RSpec.describe PublicSupportTicketCreationService do
  let(:service) { described_class.new(email: "user@example.com", subject: "Test", message: "Content") }
  let(:helper_client) { instance_double(Helper::Client) }

  before { allow(Helper::Client).to receive(:new).and_return(helper_client) }

  describe "#call" do
    it "returns success when helper creates conversation" do
      allow(helper_client).to receive(:create_conversation_for_unauthenticated_user)
        .and_return(success: true, conversation_id: "123", conversation_slug: "123")

      result = service.call
      expect(result).to include(success: true, ticket_id: "123")
    end

    it "returns failure when helper fails" do
      allow(helper_client).to receive(:create_conversation_for_unauthenticated_user)
        .and_return(success: false, error: "Service down")

      result = service.call
      expect(result).to include(success: false, error: "Service down")
    end
  end
end
