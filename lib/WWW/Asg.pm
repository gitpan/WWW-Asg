package WWW::Asg;
use strict;
use warnings;
use utf8;

use Carp;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex);
use HTML::TreeBuilder::XPath;
use Encode;
use URI;
use DateTime::Format::ISO8601;
use DateTime::Format::Strptime;

#use Smart::Comments;

our $VERSION = '0.01';

my $strp = DateTime::Format::Strptime->new( 
    pattern => '%Y.%m.%d %H:%M',
    locale    => 'ja_JP',
    time_zone => 'Asia/Tokyo', 
);
my %default_condition = (
    q => '',
    searchVideo => 'true',
    minimumLength => '',
    searchCategory => 'any',
    sort => 'date',
);

sub new {
    my ( $class, %opt ) = @_;
    my $self = bless {%opt}, $class;

    $self->{ua} = LWP::UserAgent->new unless $self->{ua};

    $self;
}

sub search {
    my ( $self, %condition ) = @_;
    %condition = ( %default_condition, %condition );
    
    my $uri = URI->new('http://asg.to/search');
    $uri->query_form(\%condition);
    my $res = $self->{ua}->get( $uri->as_string );
    return () unless $res->is_success;

    $self->_extract_videos( $res->decoded_content );
}

sub latest_videos {
    my ( $self, $page ) = @_;
    $page ||= 1;
    my $res = $self->{ua}->get("http://asg.to/new-movie?page=$page");
    return () unless $res->is_success;

    $self->_extract_videos( $res->decoded_content );
}

sub download_flv {
    my ( $self, $mcd, $filepath, $cb ) = @_;
### $mcd
### $filepath

    if ( not $mcd or not $filepath ) {
        croak "mcd and filepath is required.";
    }

    my $res = $self->{ua}->get("http://asg.to/contentsPage.html?mcd=$mcd");
    croak "Can't get contentsPage html." unless $res->is_success;

    my $html = $res->decoded_content;

    my $pt = $self->_pt($html);
    croak "Can't not scrape pt." unless $pt;

    my $st = $self->_st( $mcd, $pt );
    croak "Can't not scrape st." unless $st;

### $pt
### $st
    my $xml_res =
      $self->{ua}->get("http://asg.to/contentsPage.xml?mcd=$mcd&pt=$pt&st=$st");
    croak "Can't get contentsPage xml." unless $xml_res->is_success;

    my $url = $self->_movieurl( $xml_res->decoded_content );
    croak "Can't find movieurl in xml." unless $url;

    eval {
        my %options = ( ":content_file" => $filepath );
        if ($cb) {
            $options{":content_cb"} = $cb;
        }
        $self->{ua}->get( $url, %options );
    };
    if ($@) {
        croak "Failed downlaod. mcd: $mcd";
    }

    return $filepath;
}

sub _extract_videos {
    my ( $self, $html ) = @_;

    my $tree = HTML::TreeBuilder::XPath->new;
    $tree->parse($html);

    my $video_nodes = $tree->findnodes('//div[@id="list"]/div');

    my @videos = ();
    foreach my $node (@$video_nodes) {
        my $video = $self->_extract_video($node);
        next if not $video or not %$video;
        push @videos, $video;
    }

    @videos;
}

sub _extract_video {
    my ( $self, $node ) = @_;
    my $video = {};

    my $link_node = $node->findnodes('h3/a')->[0];
    return undef unless $link_node;

    # url
    my $url = $link_node->findvalue('@href');
    return undef
      unless $url =~ /(http:\/\/asg\.to)?\/contentsPage\.html\?mcd=([^?&]+)/;
    $video->{url} = "http://asg.to$url";

    # mcd
    $video->{mcd} = $2;

    # title
    my $title = $link_node->findvalue('@title');
    $title = $1 if $title =~ /.+アダルト動画:(.+)/;
    $video->{title} = $self->_trim($title);

    my $list_info_nodes = $node->findnodes('div[@class="list-info"]/p');

    # description
    my $description = $list_info_nodes->[3]->findvalue('.');
    $description = $1 if $description =~ /.*紹介文：\s*(.+)/;
    $video->{description} = $self->_trim($description);

    # thumbnail
    $video->{thumbnail} = $node->findvalue('a/img[@class="shift-left"]/@src');

    # date
    my $date = $list_info_nodes->[0]->findvalue('.');
    $video->{date} = $self->_date($date);

    # ccd
    my $ccd_node = $list_info_nodes->[1]->findnodes('a')->[0];
    my $ccd      = $ccd_node->findvalue('@href');
    if ( $ccd =~ /(http:\/\/asg\.to)?\/categoryPage\.html\?ccd=([^?&]+)/ ) {
        $video->{ccd} = $2;
    }
    $video->{ccd_text} = $self->_trim($ccd_node->findvalue('.'));

    # play time
    my $play_time = $list_info_nodes->[2]->findvalue('.');
    if ( $play_time =~ /.*\s([0-9]{1,3}:[0-9]{1,2}).*/ ) {
        my $play_time_text = $1;
        my @splited        = split ':', $play_time_text;
        my $play_time_sec  = int( $splited[0] ) * 60 + int( $splited[1] );
        $video->{play_time}      = $play_time_sec;
        $video->{play_time_text} = $self->_trim($play_time_text);
    }

### $video
    return $video;
}

sub _pt {
    my ( $self, $html ) = @_;
    return undef unless $html =~ m/.*urauifla\(\s*("|')([^\)]+?)("|')\).*/s;
    return undef unless $2    =~ /.*&pt=([^&]+).*/;
    return $1;
}

sub _st {
    my ( $self, $mcd, $pt ) = @_;
    my $d = "---===XERrr3nmsdf8874nca===---";
    my $seed = $d . $mcd . substr( $pt, 0, 8 );
    return md5_hex($seed);
}

sub _movieurl {
    my ( $self, $xml ) = @_;
    if ( $xml =~ m/.*<movieurl>(.+?)<\/movieurl>.*/s ) {
        return $1;
    }
    else {
        return undef;
    }
}

sub _date {
    my ( $self, $date_str ) = @_;
    $self->_trim($date_str);

    my $dt = undef;
    if ( $date_str =~ /.*([0-9]{2,4}\.[0-9]{2}\.[0-9]{2} [0-9]{2}:[0-9]{2}).*/ ) {
        my $date = "20" . $1;
        $dt = $strp->parse_datetime($date);
    }
    elsif ( $date_str =~ /.*([0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2}Z)?).*/ ){
        my $date = $1;
        $dt = DateTime::Format::ISO8601->new->parse_datetime($date);
    }
    else {
        return undef;
    }

    return $dt->iso8601; 
}

sub _trim {
    my ($self, $str) = @_;
    $str =~ s/^[\s　]*(.*?)[\s　]*$/$1/ if $str;
    return $str;
}

1;

__END__

=head1 NAME

WWW::Asg - Get video informations from Asg.to 

=head1 SYNOPSIS

    use WWW::Asg;

    my $asg = WWW::Asg->new();
    my @videos = $asg->latest_videos($page);
    foreach my $v ( @videos ) {
        my $filepath = "/tmp/$v->{mcd}.flv";
        $asg->download_flv($v->{mcd}, $filepath);
    }

=head1 AUTHOR

Tatsuya Fukata C<< <tatsuya.fukata@gmail.com> >>

=head1 LICENCE AND COPYRIGHT

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
