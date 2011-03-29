package Mojolicious::Static;
use Mojo::Base -base;

use File::Basename 'dirname';
use File::stat;
use File::Spec;
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Command;
use Mojo::Content::Single;
use Mojo::Path;

has [qw/default_static_class root/];

# "Valentine's Day's coming? Aw crap! I forgot to get a girlfriend again!"
sub dispatch {
  my ($self, $c) = @_;

  # Already rendered
  return if $c->res->code;

  # Canonical path
  my $path = $c->req->url->path->clone->canonicalize->to_string;

  # Parts
  my @parts = @{Mojo::Path->new->parse($path)->parts};

  # Shortcut
  return 1 unless @parts;

  # Prevent directory traversal
  return 1 if $parts[0] eq '..';

  # Serve static file
  unless ($self->serve($c, join('/', @parts))) {

    # Rendered
    $c->stash->{'mojo.static'} = 1;
    $c->rendered;

    return;
  }

  return 1;
}

sub serve {
  my ($self, $c, $rel, $root) = @_;

  # Root
  $root = $self->root unless defined $root;

  # Append path to root
  my $file = File::Spec->catfile($root, split('/', $rel));

  # Extension
  $file =~ /\.(\w+)$/;
  my $ext = $1;

  # Type
  my $type = $c->app->types->type($ext) || 'text/plain';

  # Response
  my $res = $c->res;

  # Asset
  my $asset;

  # Modified
  my $modified = $self->{_modified} ||= time;

  # Size
  my $size = 0;

  # Root for bundled files
  $self->{_root}
    ||= File::Spec->catdir(File::Spec->splitdir(dirname(__FILE__)), 'public');

  # Bundled file
  my $bundled = File::Spec->catfile($self->{_root}, split('/', $rel));

  # Files
  for my $path ($file, $bundled) {

    # Exists
    if (-f $path) {

      # Readable
      if (-r $path) {

        # Modified
        my $stat = stat($path);
        $modified = $stat->mtime;

        # Size
        $size = $stat->size;

        # Content
        $asset = Mojo::Asset::File->new(path => $path);
      }

      # Exists, but is forbidden
      else {
        $c->app->log->debug(qq/File "$rel" forbidden./);
        $res->code(403) and return;
      }

      # Done
      last;
    }
  }

  # Inline file
  if (!$asset && defined(my $file = $self->_get_inline_file($c, $rel))) {
    $size  = length $file;
    $asset = Mojo::Asset::Memory->new->add_chunk($file);
  }

  # Found
  if ($asset) {

    # Request
    my $req = $c->req;

    # Request headers
    my $rqh = $req->headers;

    # Response headers
    my $rsh = $res->headers;

    # If modified since
    if (my $date = $rqh->if_modified_since) {

      # Not modified
      my $since = Mojo::Date->new($date)->epoch;
      if (defined $since && $since == $modified) {
        $res->code(304);
        $rsh->remove('Content-Type');
        $rsh->remove('Content-Length');
        $rsh->remove('Content-Disposition');
        return;
      }
    }

    # Start and end
    my $start = 0;
    my $end = $size - 1 >= 0 ? $size - 1 : 0;

    # Range
    if (my $range = $rqh->range) {
      if ($range =~ m/^bytes=(\d+)\-(\d+)?/ && $1 <= $end) {
        $start = $1;
        $end = $2 if defined $2 && $2 <= $end;
        $res->code(206);
        $rsh->content_length($end - $start + 1);
        $rsh->content_range("bytes $start-$end/$size");
      }
      else {

        # Not satisfiable
        $res->code(416);
        return;
      }
    }
    $asset->start_range($start);
    $asset->end_range($end);

    # Response
    $res->code(200) unless $res->code;
    $res->content->asset($asset);
    $rsh->content_type($type);
    $rsh->accept_ranges('bytes');
    $rsh->last_modified(Mojo::Date->new($modified));
    return;
  }

  return 1;
}

sub _get_inline_file {
  my ($self, $c, $rel) = @_;

  # Protect templates
  return if $rel =~ /\.\w+\.\w+$/;

  # Class
  my $class =
       $c->stash->{static_class}
    || $ENV{MOJO_STATIC_CLASS}
    || $self->default_static_class
    || 'main';

  # Inline files
  my $inline = $self->{_inline_files}->{$class}
    ||= [keys %{Mojo::Command->new->get_all_data($class) || {}}];

  # Find inline file
  for my $path (@$inline) {
    return Mojo::Command->new->get_data($path, $class) if $path eq $rel;
  }

  # Nothing
  return;
}

1;
__END__

=head1 NAME

Mojolicious::Static - Serve Static Files

=head1 SYNOPSIS

  use Mojolicious::Static;

=head1 DESCRIPTION

L<Mojolicious::Static> is a dispatcher for static files with C<Range> and
C<If-Modified-Since> support.

=head1 FILES

L<Mojolicious::Static> has a few popular static files bundled.

=head2 C<amelia.png>

Amelia Perl logo.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<failraptor.png>

The Failraptor.

  Copyright (C) 2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<favicon.ico>

Mojolicious favicon.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<mojolicious-arrow.png>

Mojolicious arrow for C<not_found> template.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<mojolicious-black.png>

Black Mojolicious logo.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<mojolicious-box.png>

Mojolicious box for C<not_found> template.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<mojolicious-clouds.png>

Mojolicious clouds for C<not_found> template.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<mojolicious-pinstripe.gif>

Mojolicious pinstripe effect for multiple templates.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<mojolicious-white.png>

White Mojolicious logo.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C<css/prettify-mojo.css>

Mojolicious theme for C<prettify.js>.

  Copyright (C) 2010-2011, Sebastian Riedel.

Licensed under the CC-SA License, Version 3.0
L<http://creativecommons.org/licenses/by-sa/3.0>.

=head2 C</js/jquery.js>

  Version 1.5.1

jQuery is a fast and concise JavaScript Library that simplifies HTML document
traversing, event handling, animating, and Ajax interactions for rapid web
development. jQuery is designed to change the way that you write JavaScript.

  Copyright 2011, John Resig.

Licensed under the MIT License, L<http://creativecommons.org/licenses/MIT>.

=head2 C</js/prettify.js>

  Version 21-Jul-2010

A Javascript module and CSS file that allows syntax highlighting of source
code snippets in an html page.

  Copyright (C) 2006, Google Inc.

Licensed under the Apache License, Version 2.0
L<http://www.apache.org/licenses/LICENSE-2.0>.

=head1 ATTRIBUTES

L<Mojolicious::Static> implements the following attributes.

=head2 C<default_static_class>

  my $class = $static->default_static_class;
  $static   = $static->default_static_class('main');

The dispatcher will use this class to look for files in the C<DATA> section.

=head2 C<root>

  my $root = $static->root;
  $static  = $static->root('/foo/bar/files');

Directory to serve static files from.

=head1 METHODS

L<Mojolicious::Static> inherits all methods from L<Mojo::Base>
and implements the following ones.

=head2 C<dispatch>

  my $success = $static->dispatch($c);

Dispatch a L<Mojolicious::Controller> object.

=head2 C<serve>

  my $success = $static->serve($c, 'foo/bar.html');

Serve a specific file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
