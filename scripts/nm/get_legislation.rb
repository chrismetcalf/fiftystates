require File.join(File.dirname(__FILE__), '..', 'rbutils', 'legislation')

module NewMexico  
  include Scrapable
  
  SESSION_LOCATOR = "http://www.nmlegis.gov/lcs/locator.aspx"
  
  class Bill
    attr_reader :session
    def initialize(xml, year, session)
      if year < 1996
        raise NoDataForYearError(year, "No data available online before 1996")
      end
      
      @data = xml
      @year = year
      @session = session
    end
    
    def chamber
      @data.at('measure').inner_text =~ /^h/i ? 'lower' : 'upper'
    end
    
    def bill_id
      @data.at('measure').inner_text
    end
    
    def name
      @data.at('shorttitle').inner_text
    end
    
    def remote_url
      normalize_detail_url(@data.at('actionlink').inner_text)
    end
    
    def primary_sponsor
      detail_page.at('authors/principal/p_name').inner_text.strip
    end
    
    def actions
      hs = detail_page.at('msr_hs').inner_text.strip
      detail_page.search('action').collect do |action|
        text = action.at('act_desc').inner_text.strip
                          #["date", "(s/h/nil)", "s,h,nil", "text"]
        parts = text.scan(/([0-9]{2}\/[0-9]{2})\s*(\((S|H)\)|\s*)(.*)$/i)[0]
        chamber = parts[2].nil? ? '' : parts[2] == 'H' ? 'lower' : 'upper'
        {
          :action_chamber => chamber, 
          :action_text => parts[3], 
          :action_date => Time.parse("#{parts[0]} #{@year}").strftime('%m/%d/%Y')
        }
      end
    end
    
    def versions
      out = []
      types = %w(current intro cmtesub passed asg confrpts amendments vetomsg).join(',')
      detail_page.search(types).each do |v|
        case v.name
          when 'vetomsg'    then url = v.at("veto_other").inner_text.strip
          when 'confrpts'   then url = v.at("cr_other").inner_text.strip
          when 'amendments'
            v.search('amrpt, ham, sam').each do |amd|
              url = amd.at("#{amd.name}_other").inner_text.strip
              out << {:version_name => 'ammendment', :version_url => normalize_version_url(url)}
            end
          else url = v.at("#{v.name}_other").inner_text.strip
        end
        out << {:version_name => v.name, :version_url => normalize_version_url(url)}
      end
      out
    end
    
    def detail_page
      @detail_page ||= Hpricot(open(remote_url))
    end
    
    def to_hash
      {
        :bill_state => 'ms',
        :bill_chamber => chamber,
        :bill_session => @session,
        :bill_id => bill_id,
        :bill_name => name,
        :remote_url => remote_url.to_s
      }
    end
    
    private
      def normalize_detail_url(url)
        path = "#{@year}/pdf/#{url.strip.split('../').last}"
        URI.parse('http://billstatus.ls.state.ms.us') + path
      end
      
      def normalize_version_url(url)
        path = url.strip.split('../').last
        URI.parse('http://billstatus.ls.state.ms.us') + path
      end
  end
  
  # A session of the legislature
  class Session
    attr_reader :year, :name, :url
    @@sessons = Hash.new

    def Session.get_sessions(year)
  
      puts @@sessions.inspect
      
      # Load our cached set of sessions       
      doc = Hpricot(open("http://www.nmlegis.gov/lcs/locator.aspx"))
      (doc/'//table[@id=ctl00_mainCopy_Locators]/tr/td/a').each do |session_link|
        # Get the session details link from the href
        link = "http://www.nmlegis.gov/lcs/#{session_link['href']}"

        # Parse the year and name from the content
        year = nil
        name = nil
        match = session_link.inner_html.match %r{^<span[^>]+>(\d+)</span>[^<]*<span[^>]+>(.+)</span>[^<]*<span[^>]+>(.+)</span>}
        if !match.nil?
          year = match[1]
          name = "#{match[1]} #{match[2]} #{match[3]}"
        else
          $stderr.puts "Could not parse session row: #{session_link.to_html}"
        end

        session = Session.new(year, name, link)
        @@sessions[year].push(session)
      end
      @@sessions[year]
    end
    
    # Default initializer
    def initialize(year, name, url)
      @year = year
      @name = name
      @url = url
    end    
  end
  
  def self.state
    "nm"
  end
  
  # Entry point for scraper. 
  def self.scrape_bills(chamber, year)
    puts "Sessions: " + Sessions.get_sessions(2006).inspect
  
  end
end

NewMexico.run