class Offer < ActiveRecord::Base
  belongs_to :campaign
  belongs_to :instagramer
  belongs_to :campaign_post
  has_many :offer_tracks

  STATUS = [STARTED='start', PENDING='pending', COMPLETED='completed', CANCELLED='cancelled']

  validates :campaign, :instagramer, :status, :start_date, :campaign_post_id, presence: true

  delegate :title, to: :campaign
  delegate :handle, :score, to: :instagramer, prefix: true

  after_create :update_amount
  before_save :update_image_and_caption

  mount_uploader :image, ImageUploader

  scope :started, -> { where(status: STARTED)}
  scope :cancelled, -> { where(status: CANCELLED)}
  scope :pending, -> { where(status: PENDING) }
  scope :completed, -> { where(status: COMPLETED) }
  scope :active, -> { where(status: [PENDING, COMPLETED]) }
  scope :not_active, -> { where.not(status: [PENDING, COMPLETED]) }
  scope :not_cancelled, -> { where.not(status: CANCELLED) }

  def started?; status == STARTED end
  def verified?; status == PENDING || status == COMPLETED end
  def pending?; status == PENDING end

  def post_title
    campaign_post.title
  end

  def pending!
    self.update(status: PENDING, start_date: Time.current, end_date: nil)
  end

  def verify?
    status == STARTED || status == CANCELLED
  end

  def tracked_days
    offer_tracks.where("tracked_at >= ?", self.start_date).pluck(:tracked_at).map(&:to_date).uniq.count
  end

  def self.followers
    active_count = all.active.joins(:instagramer).sum("instagramers.followers")
    cancelled_count = all.where.not(id: all.active.pluck(:id)).joins(:instagramer).sum('instagramers.followers')
    (active_count + ENV['FOLLOWER_CANCELLED_COUNTER_RATE'].to_f * cancelled_count).to_i
  end

  def complete!
    last_track = offer_tracks.last
    self.update(
      status: COMPLETED,
      end_date: Date.current,
      likes: last_track.try(:likes),
      comments: last_track.try(:comments),
      posts: last_track.try(:posts)
    )
    instagramer.balance += self.instagramer_amount
    instagramer.save

    campaign.budget = campaign.budget - self.sponsor_amount
    campaign.save
  end

  def instagrammer_price
    return campaign.fixed_price.to_f if campaign.fixed_price?
    ScorePrice.influencer_price(instagramer.adjusted_score)
  end

  def sponsor_price
    return campaign.fixed_price.to_f if campaign.fixed_price?
    ScorePrice.sponsor_price(instagramer.adjusted_score)
  end

  def cancel!
    self.update(status: CANCELLED, end_date: Date.current)
  end

  def track!(params)
    self.pending! if self.verify?
    track = offer_tracks.build
    track.likes = params['likes']['count']
    track.comments = params['comments']['count']
    track.posts = params['post_count']
    track.tracked_at = Time.current
    track.save

    self.likes = track.likes
    self.comments = track.comments
    self.posts = track.posts
    self.save
  end

  def send_verification
    to = instagramer.phone
    client = Twilio::REST::Client.new
    begin
      client.messages.create(
        from: '+17605304711',
        to: to,
        body: "To complete the verification process of accepted post, please post this image and caption to your instagram handle. "\
              "We will send caption content with separate SMS.",
        media_url: image.url
      )

      client.messages.create(
        from: '+17605304711',
        to: to,
        body: "#{caption} #QS"
      )
      true
    rescue => e
      Rollbar.error(e)
      false
    end
  end

  private

  def update_amount
    self.instagramer_amount = instagrammer_price
    self.sponsor_amount = sponsor_price
    self.save
  end

  def update_image_and_caption
    if campaign_post_id_changed?
      self.remote_image_url = campaign_post.image.url
      self.caption = campaign_post.caption
    end
    true
  end
end
