FROM ruby
RUN git init
ADD Gemfile* ./
ADD *.gemspec ./
RUN bundle install