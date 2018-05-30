class CampaignMatch

  def initialize(campaign, influencer)
    @campaign = campaign
    @influencer = influencer
  end

  def self.available_campaigns(influencer)
    campaigns = Campaign.active
                  .where('campaigns.min_score <= ? and campaigns.max_score >= ?', influencer.adjusted_score, influencer.adjusted_score)
                  .where("campaigns.exclude = '{}' OR ? != ANY (campaigns.exclude)", influencer.status)
                  .where.not(id: influencer.offers.pluck(:campaign_id))
    campaigns.select { |campaign| CampaignMatch.new(campaign, influencer).valid? }
  end

  def self.available_influencers(campaign)
    influencers = Instagramer.verified.subscribed.where(score: campaign.min_score..campaign.max_score)
    influencers.select { |influencer| CampaignMatch.new(campaign, influencer).valid? }
  end

  def self.matched_influencers_based_on_campaign_categories(influencers, campaign_categories)
    return influencers.select{ |instagramer| instagramer.instagramer_categories.where(category_id: campaign_categories).present? }
  end

  def self.reputation_criteria reputation, unreviewed
    case reputation
      when 'unreviewed' then ['unreviewed']
      when 'safe' then ['safe']
      when 'appropriate' then ['safe','appropriate']
      when 'non-pc' then ['safe','appropriate','non-pc']
    end.unshift(unreviewed).compact
  end

  def self.filter_influencers_based_on_location(influencers, locations)
    influencers.select{ |instagramer| if_matched_with_any_location?(instagramer,locations) }
  end

  def self.if_matched_with_any_location?(instagramer, locations)
    locations.collect{ |location| Location.within?(location,instagramer.latlon) }.include? true
  end

  # [MLN] Remove after confirming previous location logic fix
  def self.matched_influencers_on_location(influencers, location)
    influencers = influencers.select { |influencer| influencer.geocoded? }
    return influencers.select{ |instagramer| if_within_location?(instagramer, location) }
  end

  # [MLN] Remove after confirming previous location logic fix
  def self.if_within_location?(instagramer, location)
    zip = location[0][:zip_code]
    loc_distance = location[0][:distance]

    return false if zip.blank? || !instagramer.geocoded?

    point_1 = Geocoder.coordinates(zip)
    point_2 = instagramer.latlon
    distance = Geocoder::Calculations.distance_between(point_1, point_2)

    return (distance < loc_distance.to_f) ? true : false
  end

  def self.show_available_influencers(criteria)
    popularity = criteria[:popularity].split(' ')
    campaign_categories = criteria[:campaign_categories].reject{|cc| cc.blank?}

    @influencers = Instagramer.verified.subscribed

    @influencers = @influencers.where(status: reputation_criteria(criteria[:reputation],criteria[:unreviewed])) unless criteria[:reputation].eql?('lude')

    @influencers = @influencers.where("followers #{popularity[0]} ?",popularity[1]) unless popularity[0].eql?('all')

    @influencers = matched_influencers_based_on_campaign_categories(@influencers, campaign_categories) unless campaign_categories[0].eql?('all')

    @influencers = filter_influencers_based_on_location(@influencers, criteria[:locations]) unless criteria[:locations].blank?
    return @influencers
  end

  def verify_valid?
    valid?(true)
  end

  def valid?(verify = false)
    influencer_campaigns = @influencer.offers
    influencer_campaigns = influencer_campaigns.active if verify
    return false if @campaign.paused?
    return false if influencer_campaigns.pluck(:campaign_id).include? @campaign.id

    # Add condition Return influencers (influencet popularity) based on nano (<400), micro(>400) or all influencers(0-1000)
    # I believe we are no longer getting the adjusted_score - may remove
    return false if @campaign.min_score > @influencer.adjusted_score || @campaign.max_score < @influencer.adjusted_score
    return false if @campaign.exclude.present? && @campaign.exclude.include?(@campaign.status)

    if @campaign.locations.present?
      return false if @influencer.zip_code.nil? || @campaign.locations.all? { |l| !l.within?(@influencer.latlon) }
    end

    if @campaign.categories.present?
      return false if @influencer.categories.count == 0 || (@campaign.categories.pluck(:id) & @influencer.categories.pluck(:id)).blank?
    end

    return false if @campaign.available_budget < @campaign.sponsor_price(@influencer)

    # Add status of instagramer as a criteria
    # Check to see if instagramer's status is the same as status selected for criteria. It is the last dropdown on the form with label 'What type of content are influencers allowed to post?'
    # Statuses are in the instagramer model...it is not clear how they map...just do your best guess
    # STATUSES = [SAFE='safe', APPROPRIATE='appropriate', NON_PC='non-pc', UNREVIEWED='unreviewed', LUDE='lude']
    true
  end
end
