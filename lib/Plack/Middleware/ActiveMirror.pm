package Plack::Middleware::ActiveMirror;
use strict;
use warnings;
use parent 'Plack::Middleware';
our $VERSION = '0.01';

use Plack::Util::Accessor qw( cache json vary always_fetch );

use Web::Request;
use JSON ();

sub prepare_app {
    my $self = shift;
    unless ($self->json) {
        $self->json(JSON->new->canonical);
    }
    unless ($self->vary) {
        $self->vary(['path', 'all_parameters']);
    }
}

sub key_from_env {
    my ($self, $env) = @_;

    my $req = Web::Request->new_from_env($env);
    my %key_params = (
        map { $_ => $req->$_ } @{ $self->vary }
    );

    my $key = $self->json->encode(\%key_params);

    return $key;
}

sub call {
    my ($self, $env) = @_;
    my $cache = $self->cache;

    my $key = $self->key_from_env($env);

    if (!$self->always_fetch) {
        if (my $cached_response = $cache->get($key)) {
            return $cached_response;
        }
    }

    my $res = $self->app->($env);

    Plack::Util::response_cb($res, sub {
        my $res = shift;
        my @body;

        return sub {
            my $chunk = shift;

            if (!defined $chunk) {
                $cache->set($key, [ $res->[0], $res->[1], \@body ]);
                return;
            }

            push @body, $chunk;
            return $chunk;
        };
    });
}

1;
