class OffersController < ApplicationController
  before_filter :authenticate_instagramer!

  def index
    @miles = params[:miles].to_i
    @campaigns = CampaignMatch.available_campaigns(current_instagramer).sort_by(&:created_at).reverse!
    @offers = current_instagramer.offers.order(status: :desc)
  end

  def new
    @campaign = Campaign.find params[:campaign_id]
    @offer = current_instagramer.offers.build(campaign_id: @campaign.id)
    offer_verify = CampaignMatch.new(@offer.campaign, @offer.instagramer)
    unless offer_verify.verify_valid?
      redirect_to offers_path, alert: 'Campaign is not available for you, please try another campaign.'
    end
  end

  def create
    @campaign = Campaign.find params[:offer][:campaign_id]
    @campaign_post_id = params[:offer][:campaign_post_id]
    @create_offer = CreateOffer.run(
      instagramer: current_instagramer,
      campaign: @campaign,
      campaign_post_id: @campaign_post_id
    )
  end

  def verify
    @offer = current_instagramer.offers.find params[:id]
    offer_verify = CampaignMatch.new(@offer.campaign, @offer.instagramer)
    unless offer_verify.verify_valid?
      @offer.destroy
      flash[:alert] = 'Campaign is not available, please try another campaign'
      render js: "window.location.href='#{offers_path}'"
    end
    @verify_offer = VerifyPost.run(offer_id: @offer.id)
    if @verify_offer.result
      no_followers = current_instagramer.followers.nil? ? @offer.campaign.followers : @offer.campaign.followers + current_instagramer.followers
      @offer.campaign.update(followers: no_followers)
      VerifyOfferJob.set(wait: 1.days).perform_later(@offer.id)
    end
  end

  def request_verify
    @offer = current_instagramer.offers.find params[:id]
    offer_verify = CampaignMatch.new(@offer.campaign, @offer.instagramer)
    unless offer_verify.verify_valid?
      @offer.destroy
      flash[:alert] = 'Campaign is not available, please try another campaign'
      render js: "window.location.href='#{offers_path}'"
    end
    @offer.update(campaign_post_id: params[:offer][:campaign_post_id])
    @sent = @offer.send_verification
  end

  def show
    @offer = current_instagramer.offers.find params[:id]
  end
end
