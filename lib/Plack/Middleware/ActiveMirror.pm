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
        $self->vary(['path', 'all_parameters', 'method']);
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

__END__

=head1 NAME

Plack::Middleware::ActiveMirror - mirror parts of your app e.g. for offline hacking

=head1 DESCRIPTION

Hi, CPAN. My name is Shawn. I have a connectivity problem.

We have beautifully-designed Web Services (implemented by handsome
fellows!) for our C<$client> project, but we don't always have
connectivity to them. I like to hack from cafés with crappy internet,
which means lots of pain just to load a page since each page has
to make multiple requests to our web services.

So I got to thinking, why not cache the web services responses?  As
long as the responses form a reasonably current snapshot, it should
work fine. Sure, I can't expect to do everything my app supports
just with these cached responses, but at least my JavaScript loads,
and that lets me limp along well enough to continue generating
billable hours.

I tried using off-the-shelf tools first, like the wonderful Charles
Proxy (L<http://www.charlesproxy.com/>) and other Plack middleware,
but none of them quite met my needs. They can mirror sets of paths
just fine, but once you add query parameters into the mix, things
start to go south. I needed a bit more control in what was cached,
and how. Hence L<Plack::Middleware::ActiveMirror>.

=cut

