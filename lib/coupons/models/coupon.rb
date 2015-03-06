module Coupons
  module Models
    class Coupon < ActiveRecord::Base
      # Allow using `type` as a column.
      self.inheritance_column = nil

      # Set table name.
      self.table_name = :coupons

      # Set default values.
      after_initialize do
        self.code ||= Coupons.configuration.generator.call
      end

      has_many :redemptions, class_name: 'Coupons::Models::CouponRedemption'

      validates_presence_of :code
      validates_inclusion_of :type, in: %w[percentage amount]

      serialize :attachments, GlobalidSerializer

      validates_numericality_of :amount,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 100,
        only_integer: true,
        if: :percentage_based?

      validates_numericality_of :amount,
        greater_than_or_equal_to: 0,
        only_integer: true,
        if: :amount_based?

      validates_numericality_of :redemption_limit,
        greater_than_or_equal_to: 0

      validate :validate_expires_on

      def apply(options)
        input_amount = BigDecimal("#{options[:amount]}")
        discount = BigDecimal(percentage_based? ? percentage_discount(options[:amount]) : amount)
        total = [0, input_amount - discount].max

        options = options.merge(total: total, discount: discount)

        options = Coupons.configuration.resolvers.reduce(options) do |options, resolver|
          resolver.resolve(self, options)
        end

        options
      end

      def redemption_count
        coupon_redemptions_count
      end

      def expired?
        expires_on && expires_on <= Date.current
      end

      def redeemable?
        !expired? && redemption_count < redemption_limit
      end

      def to_partial_path
        'coupons/coupon'
      end

      def percentage_based?
        type == 'percentage'
      end

      def amount_based?
        type == 'amount'
      end

      private

      def percentage_discount(input_amount)
        BigDecimal("#{input_amount}") * (BigDecimal("#{amount}") / 100)
      end

      def validate_expires_on
        return if expires_on_before_type_cast.blank?
        errors.add(:expires_on, :invalid) unless expires_on.kind_of?(Date)
        errors.add(:expires_on, :coupon_already_expired) if expires_on? && expires_on < Date.current
      end
    end
  end
end
