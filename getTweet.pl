#!/usr/bin/perl

# Search tweets for sharing and output formatting contents.
# Created by azur256 on 03/20/12
# Copyright 2012 azur256. All rights reserved.

use strict;
use warnings;
use utf8;

use POSIX qw(strftime);
use Data::Dumper;
use Encode;

use LWP::UserAgent;
use HTTP::Date;
use Net::Twitter::Lite;

use Email::Sender::Simple qw(sendmail);
use Email::Simple;
use Email::Simple::Creator;
use Email::Sender::Transport::SMTP::TLS;
use Data::Recursive::Encode;

# --------------------
my $screen_name = 'azur256';
my $begin_days = 1; # デフォルト値 今日なら 0、昨日なら 1 を指定
my $end_days = 1;   # デフォルト値 遡るのが1日なら 1を指定
my $get_count = 200; # 検索する呟きの数。多くなると負荷が上がるので適当に設定

my $do_mail = 0; # メール送信するなら 1、設定が必要
my $do_file = 1; # ファイル出力するなら 1、設定が必要
my $do_print = 0; # 標準出力するなら 1、設定が必要

my $filename = 'shareTweet.txt'; # 出力ファイル名 (日付がプレフィックスで付きます)
my $to_address = 'foo@example.com'; # メール送信時のToアドレス
my $from_address = 'bar@example.com'; # メール送信時のFromアドレス
my $gmail_password = password'; # Gmailのパスワード

my $title_text = 'azur256 \'s check No. ';
my $header_text = '最近チェックしたブログエントリをご紹介します<br />';
my $body_text ='';
# --------------------

#initialize
my $data_set = [];    # ハッシュテーブルを複数セット格納する配列
my $now;
my $begin_time = 0;
my $end_time = 0;

my $twitter_service;
my $timeline;

# オプションを取得
if (defined($ARGV[0])) {
    $begin_days = $ARGV[0];
};

if (defined($ARGV[1])) {
    $end_days = $ARGV[1];
}

# 終了日は開始日からの差分なので開始日を加算する
$end_days = $end_days + $begin_days;

# 現在時刻を取得
$now = str2time(localtime());

# 現在時刻からの遡ったMachine Timeを取得する。
# 遡りが0の場合は現在時刻、1の場合は本日の0時、2の場合は昨日の0時
$begin_time = prevDate($now, $begin_days);
$end_time = prevDate($now, $end_days);

# Twitter へのコネクションの作成
$twitter_service = Net::Twitter::Lite->new();
$timeline = $twitter_service->user_timeline({id => $screen_name, count => $get_count, include_entities => 'true'});

# Twitter からのデータ抽出
foreach my $tweet (reverse(@$timeline)) {
    
    my $tweet_text = $tweet->{text};
    
    # 日付をJSTに統一 
    my $created = $tweet->{created_at};
    $created =~ s/\+0000/GMT/;
    $created = str2time($created, 'JST');
    
    # ここがフィルタ 処理対象日でかつ処理文字列があるかで検索して無ければスキップ
    # 処理対象日はmachine timeで比較する
    if ( ($end_time <= $created) and ($created < $begin_time) and ($tweet_text =~ /\[SHARE\]/i ) ) {
        
        my $comment ='';        # 自分のコメント
        my $title = '';         # ブログのタイトル
        my $long_url = '';      # ブログのURL
        my $data_record = {};   # 上記のハッシュテーブル
        
        my $dum;		# ダミー
        my $url;		# timeline_stream の URL 属性
        
        # 自分のフォーマットに合わせて split で分解する
        # x{261e}は"☞"記号
        ($dum, $comment, $title, $url) = split(/(.*)\[SHARE\](.*)\x{261e}(.*)/, $tweet_text);
        
        # urlは複数の場合があるが今回は最初の1つだけを対象にしてExpanded URLを取得する
        # 複数処理したいなら foreach my $url (@{$tweet->{entities}{urls}})のループ
        $url = (@{$tweet->{entities}{urls}})[0];
        $long_url = $url->{expanded_url};
        
        # expanded_url自体が短縮URLである可能性があるのでオリジナルを参照して変換する
        $long_url = urlExpand($long_url);
        
        # 空白文字をTrim
        trim($title);
        trim($comment);
        
        # 分かりやすさのためにハッシュにする
        # Hashを作る キー値は url, title, comment とする
        
        $data_record->{url} = $long_url;
        $data_record->{title} = $title;
        $data_record->{comment} = $comment;
        
        push @$data_set, $data_record;
    }
}

# 作成したレコードセットに対して、標準出力への出力、ファイル出力、メール送信を行う
$body_text = &makeBody(\@$data_set);

if ( $do_print ) {
    &printRecord($body_text);
}

if ( $do_file) {
    
    &outputRecord($body_text);
    
}

if ( $do_mail) {
    
    &mailRecord($body_text);
}

# 本文を作成する
sub makeBody{
    
    my $body = '';
    my $record = [];
    my $records = {};
    my $tweets_count = 0;
    
    #    $records = @_ ; 
    
    foreach $records (@_) {
        foreach $record (@$records) {
            $tweets_count += 1;
            $body .= '<hr /><br />';
            $body .= '<table border="0"><td valign="top" width="600"><a href="';
            $body .= $record->{url};
            $body .= '" target="_blank">';
            $body .= Encode::encode("utf8", $record->{title});
            $body .= '</a>';
            $body .= '<div style="font-size: 80%;"><br><strong>';
            $body .= Encode::encode("utf8", $record->{comment});
            $body .= '</strong></div>';
            $body .= '</td>';
            $body .= '<td valign="top" width="90"><a href="';
            $body .= $record->{url};
            $body .= '" target="_blank">';
            $body .= '<img border="0" src="http://capture.heartrails.com/90x60/shadow?';
            $body .= $record->{url};
            $body .= '" alt="" width="90" height="60" />';
            $body .= '</a></td>';
            $body .= '</table>' . '<br /><br />' . "\n\n";
        }
    }
    
    
    $header_text = strftime('%Y年%m月%d日 ', localtime()) . $title_text . "\n\n" . $header_text . strftime('チェックしたブログエントリの中で %Y年%m月%d日は ', localtime()) . $tweets_count . ' 件が気になりました。<br /><!--more--><br />' . "\n\n";
    
    $body = Encode::encode("utf8", $header_text) . $body;
    
    
    $body;
}

# 標準出力に出力する
sub printRecord{
    
    print $_[0];
    print "\n\n";
    
    return;
}

# ファイル出力する
sub outputRecord{
    
    $filename = strftime("%Y%m%d%H%M", localtime()) . "_" . $filename;
    open (FILE, '> ' . $filename) or die "Can't open file" . $filename;
    
    print FILE $_[0];
    print FILE "\n\n";
    
    close (FILE);
}

# 指定されたアドレスにメールを送る
sub mailRecord{
    my $email;
    
    $email = Email::Simple->create(
    header => Data::Recursive::Encode->encode(
    'MIME-Header-ISO_2022_JP' => [
    To => $to_address,
    From => $from_address,
    Subject => strftime("%Y年%m月%d日のチェック", localtime()),
    ]
    ),
    body => Data::Recursive::Encode->encode_utf8($_[0]),
    attributes => {
        content_type => 'text/plain',
        charset      => 'UTF-8',
        #            encoding     => 'base64',
    },
    );
    
    my $sender = Email::Sender::Transport::SMTP::TLS->new(
    host     => 'smtp.gmail.com',
    port     => 587,
    username => $from_address,
    password => $gmail_password,
    helo     => 'example.com',
    );
    
    my $return = sendmail($email, {transport => $sender});        
    
}

# 短縮URLの拡張
sub urlExpand{
    my $short_url = $_[0];
    my $long_url = '';
    
    my $user_agent = LWP::UserAgent->new(timeout => 10);
    my $responce = $user_agent->head($short_url);
    
    if ($responce->request->uri) {
        $long_url = $responce->request->uri;
    } else {
        $long_url = $short_url;
    }
    
    $long_url;
}

# 前後の空白文字列を削除する
sub trim{
    
    $_[0] =~ s/^\s*(.*?)\s*$/$1/;
    
}

# 指定されたMachine Timeから指定日数前の0:00:00(JST)のMachine Timeを求める
# 指定日数が0の場合は与えられた時間のMachine Timeをそのまま返す
# 指定日数が0の場合は与えられた日の0時を返す
# 指定日数が1の場合は与えられた日の前日の0時を返す
sub prevDate{
    
    my $delta = 0;
    my $base = 0;
    my ($sec, $min, $hour, $mday, $mon, $year);
    my $return;
    
    $base = $_[0];
    if (!defined($base)) {
        $base = str2time(localtime());
    }
    
    $delta = $_[1];
    if (!defined($delta)) {
        $delta = 1;
    }
    
    if ($delta != 0) {
        ($sec,$min,$hour,$mday,$mon,$year) = localtime($base-60*60*24*($delta - 1));
        $return = str2time(sprintf('%02d-%02d-%02d 00:00:00 +0900', $year+1900, $mon+1, $mday));
    } else {
        $return = $base;
    }
    
}
