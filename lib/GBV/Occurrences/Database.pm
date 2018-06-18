package GBV::Occurrences::Database;
use v5.14;

use URI::Escape;
use Time::Piece;
use HTTP::Tiny;
use List::Util qw(pairmap);
use GBV::Occurrences::API::Response;

sub new {
    my ( $class, $dbkey ) = @_;

    bless {
        dbkey    => $dbkey,
        uri      => "http://uri.gbv.de/database/$dbkey",
        srubase  => "http://sru.gbv.de/$dbkey",
        picabase => "https://gso.gbv.de/DB=2.1/",        # FIXME: don't hardcode
    }, $class;
}

sub count_via_sru {
    my ( $self, @query ) = @_;

    my $cql = join ' and ', pairmap { "pica.$a=\"$b\"" } @query;

    my $url =
        $self->{srubase}
      . "?version=1.2&operation=searchRetrieve"
      . "&query="
      . uri_escape($cql)
      . "&maximumRecords=0&recordSchema=picaxml";

    say STDERR $url;

    my $res = HTTP::Tiny->new->get($url);
    if ( $res->{success} and $res->{content} =~ /numberOfRecords>([0-9]+)</m ) {
        return $1;
    }
    else {
        error( 500, "failed to get occurrences via SRU: $url" );
    }
}

sub startswith {
    substr( $_[0], 0, length( $_[1] ) ) eq $_[1];
}

sub _concept_cql {
    my $concept = shift;

    my $uri    = $concept->{uri};
    my $scheme = $concept->{inScheme}->[0];
    my $cqlkey = $scheme->{CQLKEY};

    my $id = substr( $uri, length $scheme->{namespace} );

    if ( $cqlkey eq 'ddc' ) {
        if ( startswith( $id, 'class/' ) ) {
            $id = substr( $id, length 'class/' );
        }
        else {
            error( 400, "DDC URI not supported: $uri" );
        }
    }
    elsif ( $cqlkey eq 'rvk' || $cqlkey eq 'kab' ) {
        $id =~ s/_/ /g;
        $id =~ s/-/ - /g;
    }

    return ( $cqlkey, $id );
}

sub occurrence {
    my ( $self, @concepts ) = @_;

    my $occurrence = {
        database => { uri => $self->{uri} },
        modified => localtime->datetime . localtime->strftime('%z')
    };

    my @query = map { _concept_cql($_) } @concepts;

    $occurrence->{memberSet} = [
        map {
            {
                uri      => $_->{uri},
                inScheme => [ { 'uri' => $_->{inScheme}->[0]->{uri} } ]
            }
        } @concepts
    ];

    $occurrence->{count} = $self->count_via_sru(@query);

    # TODO: check IKT
    $occurrence->{url} =
        $self->{picabase}
      . "CMD?ACT=SRCHA&IKT=1016&SRT=YOP&TRM="
      . uri_escape( join ' ', pairmap { "$a \"$b\"" } @query );

    return $occurrence;
}

1;

=head1 NAME

GBV::Occurrences::Database - Database to query occurrences from

=head1 DESCRIPTION

By now only PICA databases are supported but occurrences could be retrieved
from any other source as well.

=cut
