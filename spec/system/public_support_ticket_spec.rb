# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Public Support Ticket System", type: :system do
  let(:user) { create(:user, email: "supporter@example.com") }

  before do
    allow(GlobalConfig).to receive(:get).with("public_support_tickets_enabled").and_return(true)
    allow(GlobalConfig).to receive(:get).with("HELPER_WIDGET_HOST").and_return("https://test-helper.dev")
    allow(GlobalConfig).to receive(:get).with("RECAPTCHA_SIGNUP_SITE_KEY").and_return("test_site_key")
  end

  it "displays support form" do
    visit "/support/new-ticket"
    expect(page).to have_content("Contact Support")
    expect(page).to have_field("Email")
    expect(page).to have_button("Send Message")
  end

  it "creates ticket with valid data", js: true do
    user
    allow_any_instance_of(PublicController).to receive(:valid_recaptcha_response?).and_return(true)
    allow_any_instance_of(PublicSupportTicketCreationService).to receive(:call)
      .and_return(success: true, ticket_id: "ticket_123")

    visit "/support/new-ticket"
    fill_in "email", with: user.email
    fill_in "subject", with: "Help needed"
    fill_in "message", with: "Cannot access products"
    click_button "Send Message"

    expect(page).to have_current_path("/support/tickets/ticket_123/confirmation")
    expect(page).to have_content("ticket_123")
  end

  it "displays confirmation page" do
    visit "/support/tickets/test_id/confirmation"
    expect(page).to have_content("Support Ticket Submitted")
    expect(page).to have_content("test_id")
  end
end
