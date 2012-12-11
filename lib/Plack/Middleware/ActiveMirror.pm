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

    unless ($self->cache) {
        require Carp;
        Carp::confess("ActiveMirror requires a `cache`");
    }

    unless ($self->vary) {
        $self->vary(['path', 'all_parameters', 'method']);
    }

    unless ($self->json) {
        $self->json(JSON->new->canonical);
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

=head1 SYNOPSIS

    enable_if { $_[0]->{PATH_INFO} =~ m{^/-/} }
        ActiveMirror => (
            cache => CHI->new(
                driver    => 'RawMemory',
                datastore => {},
            ),
        );

    mount '/-/' => 'Plack::App::Proxy' => (
        remote  => 'http://rest.example.com',
        backend => 'LWP',
    );

=head1 DESCRIPTION

Hi, CPAN. My name is Shawn. I have a connectivity problem.

We have beautifully-designed Web Services (implemented by handsome
fellows!) for our C<$client> project, but we don't always have
connectivity to them. I like to hack from cafés with crappy internet,
which means lots of pain just to load a page since each page has
to make multiple requests to our web services.

So I got to thinking, why not cache the web services responses?  As
long as the responses form a coherent, reasonably current snapshot,
it should work fine. Sure, I can't expect to do everything my app
supports just with these cached responses, but at least my JavaScript
loads, and that lets me limp along well enough to continue generating
billable hours. It's also fast as hell.

I tried using off-the-shelf tools first, like the wonderful Charles
Proxy (L<http://www.charlesproxy.com/>) and other Plack middleware,
but none of them quite met my needs. They can mirror sets of paths
just fine, but once you add query parameters into the mix, things
start to go south. I needed a bit more control in what was cached,
and how.

I also wanted to make sure that in the normal case of perfect
connectivity, my application would behave normally: every request
would proxy to my web services as usual. There would be an additional
side effect of every response being put into a cache, effectively
generating a partial, static mirror of your web services. Then,
when connectivity goes down the drain, I can flip a switch and now
ActiveMirror can serve responses out of cache on behalf of the
now-inaccessible web services.

=head1 THE CACHE

L<Plack::Middleware::ActiveMirror> relies on L<CHI> to manage its
cache. This gives you enormous flexibility in how your responses
are stored: in memory, on disk, in a database, whatever L<CHI>
supports. This means that you must pass an instance of L<CHI> to
get yourself going. (The only L<CHI> API that this module uses is
C<< ->get($key) >> and C<< ->set($key, $value) >> so if you're
sneaky you can provide any kind of cache object -- but! I explicitly
do I<not> promise that this module will continue using only those
two methods with those arguments in perpetuity).

=head1 OPTIONS

=head2 C<cache>

An initialized L<CHI> object that will hold your cached responses.
This parameter is required.

=head2 C<vary>

An array reference containing the methods to call on L<Web::Request>
to build a cache key. By default, we vary the cache key by C<path>,
C<method> (GET, POST, etc), and C<all_parameters>.

=head2 C<always_fetch>

If set to a true value, then ActiveMirror will not serve any requests
out of cache. The request will always be serviced by upstream. The
point of this option (instead of just removing ActiveMirror) is to
build up your cache for when you lose connectivity. So, by default,
set C<always_fetch>, but then when you go offline, turn off
C<always_fetch>.

=head2 C<json>

An instance of L<JSON> simply kept around to avoid having to
initialize it every request. You can pass in your own L<JSON> object
if you need different options for some reason; be sure to set
C<canonical>!

=head1 SEE ALSO

L<Plack::Middleware::Cache>

=head1 AUTHOR

Shawn M Moore - C<code@sartak.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Infinity Interactive.

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system
itself.

=cut

