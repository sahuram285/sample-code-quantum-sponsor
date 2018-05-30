require 'open-uri'
require 'phashion'
require 'fuzzystringmatch'

class VerifyPost < ActiveInteraction::Base
  integer :offer_id

  validates :offer_id, presence: true

  def execute
    @offer = Offer.find offer_id
    @handle = @offer.instagramer.handle
    scraper = InstagramScraper.new @handle
    if scraper.available? && !scraper.private?
      begin
        post = nil
        valid = false
        count_to_check = @offer.verify? ? 20 : 100
        scraper.each(count_to_check) do |p|
          valid = valid_post? p
          post = p if valid
          valid
        end

        if valid
          post['post_count'] = scraper.post_count
          @offer.track!(post)
        else
          @offer.cancel!
        end
        valid
      rescue => e
        Rollbar.error(e)
        false
      end
    else
      @offer.cancel!
      false
    end
  end

  def valid_post?(post)
    post_caption = post['caption'].try :[], 'text'
    post_image_url = post['images']['standard_resolution']['url']

    jarow = FuzzyStringMatch::JaroWinkler.create(:pure)
    text_distance = jarow.getDistance(post_caption || '', "#{@offer.caption} #QS")

    if text_distance >= 0.95
      campaign_image = RemoteImage.new(@offer.image.url).download!
      post_image = RemoteImage.new(post_image_url).download!

      img_user = Phashion::Image.new(post_image.path)
      img_original = Phashion::Image.new(campaign_image.path)

      distance = img_original.distance_from(img_user)
      campaign_image.clear!
      post_image.clear!

      Rails.logger.error '---- Verify Image Distance ----'
      Rails.logger.error "@#{@handle} - #{distance}"
      Rails.logger.error '---- Verify Image Distance ----'
      Rails.logger.error '---- Verify Post Caption ----'
      Rails.logger.error "`#{post_caption}` - `#{@offer.caption} #QS`"
      Rails.logger.error '---- Verify Post Caption ----'

      distance < 10
    else
      false
    end
  end
end