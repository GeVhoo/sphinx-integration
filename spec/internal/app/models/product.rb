# frozen_string_literal: true

class Product < ActiveRecord::Base
  define_index('product') do
    indexes 'name', as: :name

    set_property rt: true
    set_property source_no_grouping: true
    set_property rotation_time: 1.minute
  end
end
