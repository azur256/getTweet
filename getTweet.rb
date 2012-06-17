require "rubygems"
require "date"
require 'net/http'
require 'uri'
require "twitter"

GetCount = 50								# 取得するツィートの数
ScreenName = "azur256"						# Twitterのスクリーン名
REGEXPKeyword = /(.*)\[SHARE\](.*)☞(.*)/i
# 正規表現で記載
DefaultStartDay = 0
DefaultPeriod = 1
FileName = "shareTweet.txt"

# 指定した期間の中のツィートかどうかの判定
def in_period(check_date, start, period)
	now_date   = Date.today
	begin_date = now_date - start - period
	end_date   = now_date - start
	if begin_date < check_date and check_date <= end_date then
		return true
	else
		return false
	end
end

# 短縮URLの展開 5回のネストまでは辿る
def expand_url(url, limit = 5)
	begin
		uri = url.kind_of?(URI) ? url : URI.parse(url)
		Net::HTTP.start(uri.host, uri.port) { |io|
			response = io.head(uri.path)
			case response
			when Net::HTTPSuccess
				response['Location'] || uri.to_s
			when Net::HTTPRedirection
				if limit > 1 then
					expand_url(response['Location'], limit -1)
				else
					response['Location'] || uri.to_s
				end
			else
				url
			end
		}
	rescue
		url
	end
end

def get_counter
	count = Date.today().jd - 2455986
	count.to_s
end

def make_capture_tag(url)
	"<a href=\"" + url + "\" target=\"_blank\"><img alt=\"\" border=\"0\" height=\"60\" src=\"http://capture.heartrails.com/90x60/shadow?" + url + "\" width=\"90\" /></a>"
end

# 引数の取得、無ければデフォルト値を使う
if ARGV[0] == nil then
	start_day = DefaultStartDay
else
	start_day = ARGV[0].to_i
end
if ARGV[1] == nil then
	period = DefaultPeriod
else
	period = ARGV[1].to_i
end

# Twitterへのアクセス
tweets = Twitter.user_timeline(ScreenName, :count => GetCount)

# Entry の数
entry_count = 0
contents = ""

# tweets.reverse!
tweets.reverse_each do |tweet|

	created_time = tweet.created_at
	created_date = Date.parse(created_time.strftime("%Y-%m-%d"))

	if in_period(created_date, start_day, period) then
		if tweet.text =~ REGEXPKeyword then
			entry_count += 1
			match = tweet.text.match(REGEXPKeyword)

			comment = match[1].strip
			title   = match[2].strip
			url     = expand_url(match[3].strip)

			contents += "<div id=\"check\">"
			contents += "<div id=\"check_img\">"
			contents += make_capture_tag(url) + "</div>"
			contents += "<div id=\"check_title\">"
			contents += "<a href=\"" + url + "\" target=\"_blank\">"
			contents += title + "</a></div>"
			contents += "<div id=\"check_comment\">" + comment + "</div>"
			contents += "</div><br id=\"check_clear\">\n\n"
		end
	end

end

header  = "Check#" + get_counter() + "\n\nチェックしたブログエントリの中で "
header += Date.today().strftime("%Y年%m月%d日") + "は "
header += entry_count.to_s + " 件が気になりました。\n\n"
contents = header + contents

# ファイルへ出力
filename = DateTime.now.strftime("%Y%m%d%H%M_") + FileName
File.open(filename, "w") {|fp|
	fp.write(contents)
}
