require "rails_helper"

RSpec.describe "/listings", type: :request do
  let(:user) { create(:user) }
  let(:organization) { create(:organization) }
  let(:cl_category) { create(:classified_listing_category, cost: 1) }

  let(:params) do
    {
      classified_listing: {
        title: "Hey",
        classified_listing_category_id: cl_category.id,
        body_markdown: "hey hey my my",
        tag_list: "ruby, rails, go"
      }
    }
  end

  describe "GET /listings" do
    it "has page content" do
      get "/listings"
      expect(response.body).to include("classified-filters")
    end

    it "has page content for category page" do
      get "/listings/saas"
      expect(response.body).to include("classified-filters")
    end
  end

  describe "GETS /listings/new" do
    it "has page content" do
      get "/listings"
      expect(response.body).to include("classified-filters")
    end
  end

  describe "POST /listings" do
    before do
      create_list(:credit, 20, user_id: user.id)
      sign_in user
    end

    it "creates proper listing if credits are available" do
      post "/listings", params: params
      expect(ClassifiedListing.last.processed_html).to include("hey my")
    end

    it "spends credits" do
      num_credits = Credit.where(spent: true).size
      post "/listings", params: params
      expect(Credit.where(spent: true).size).to be > num_credits
    end

    it "adds tags" do
      post "/listings", params: params
      expect(ClassifiedListing.last.cached_tag_list).to include("rails")
    end

    it "creates the listing under the user" do
      post "/listings", params: params
      expect(ClassifiedListing.last.user_id).to eq user.id
    end

    it "creates the listing for the user if no organization_id is selected" do
      create(:organization_membership, user_id: user.id, organization_id: organization.id)
      post "/listings", params: params
      expect(ClassifiedListing.last.organization_id).to eq nil
      expect(ClassifiedListing.last.user_id).to eq user.id
    end

    it "creates the listing for the organization" do
      create(:organization_membership, user_id: user.id, organization_id: organization.id)
      params[:classified_listing][:organization_id] = organization.id
      post "/listings", params: params
      expect(ClassifiedListing.last.organization_id).to eq(organization.id)
    end

    it "does not create an org listing if a different org member doesn't belong to the org" do
      another_org = create(:organization)
      create(:organization_membership, user_id: user.id, organization_id: another_org.id)
      params[:classified_listing][:organization_id] = organization.id
      expect do
        post "/listings", params: params
      end.to raise_error Pundit::NotAuthorizedError
    end

    context "when rate limiting" do
      let(:rate_limiter) { RateLimitChecker.new(user) }

      before do
        allow(RateLimitChecker).to receive(:new).and_return(rate_limiter)
        sign_in user
      end

      it "increments rate limit for listing_creation" do
        allow(rate_limiter).to receive(:track_limit_by_action)
        post "/listings", params: params

        expect(rate_limiter).to have_received(:track_limit_by_action).with(:listing_creation)
      end

      it "returns a 429 status when rate limit is reached" do
        allow(rate_limiter).to receive(:limit_by_action).and_return(true)
        post "/listings", params: params

        expect(response.status).to eq(429)
      end
    end
  end

  describe "GET /listings/edit" do
    let(:classified_listing) { create(:classified_listing, user_id: user.id) }

    before do
      create_list(:credit, 20, user_id: user.id)
      sign_in user
    end

    it "has page content" do
      get "/listings/#{classified_listing.id}/edit"
      expect(response.body).to include("You can bump your listing")
    end
  end

  describe "PUT /listings/:id" do
    let(:classified_listing) { create(:classified_listing, user_id: user.id) }

    before do
      create_list(:credit, 20, user_id: user.id)
      sign_in user
    end

    it "updates bumped_at if action is bump" do
      put "/listings/#{classified_listing.id}", params: {
        classified_listing: { action: "bump" }
      }
      expect(ClassifiedListing.last.bumped_at).to be > 10.seconds.ago
    end

    it "updates publish if action is unpublish" do
      put "/listings/#{classified_listing.id}", params: {
        classified_listing: { action: "unpublish" }
      }
      expect(ClassifiedListing.last.published).to eq(false)
    end

    it "updates body_markdown" do
      put "/listings/#{classified_listing.id}", params: {
        classified_listing: { body_markdown: "hello new markdown" }
      }
      expect(ClassifiedListing.last.body_markdown).to eq("hello new markdown")
    end

    it "does not update body_markdown if not bumped/created recently" do
      classified_listing.update_column(:bumped_at, 50.hours.ago)
      put "/listings/#{classified_listing.id}", params: {
        classified_listing: { body_markdown: "hello new markdown" }
      }
      expect(ClassifiedListing.last.body_markdown).not_to eq("hello new markdown")
    end

    it "updates other fields" do
      put "/listings/#{classified_listing.id}", params: {
        classified_listing: { body_markdown: "hello new markdown", title: "New title!", tag_list: "new, tags, hey" }
      }
      expect(ClassifiedListing.last.title).to eq("New title!")
      expect(ClassifiedListing.last.cached_tag_list).to include("hey")
    end

    it "does not update other fields" do
      classified_listing.update_column(:bumped_at, 50.hours.ago)
      put "/listings/#{classified_listing.id}", params: {
        classified_listing: { body_markdown: "hello new markdown", title: "New title!", tag_list: "new, tags, hey" }
      }
      expect(ClassifiedListing.last.title).not_to eq("New title!")
      expect(ClassifiedListing.last.cached_tag_list).not_to include("hey")
    end
  end
end
