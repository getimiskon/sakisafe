#!/usr/bin/perl
# This file is part of sakisafe.

use if $^O eq "openbsd", OpenBSD::Pledge, qw(pledge);
use Mojolicious::Lite -signatures;
use Mojolicious::Routes::Pattern;
use List::MoreUtils qw(uniq);
use Carp;
use Term::ANSIColor;
use English;
use MIME::Types;
use warnings;
use experimental 'signatures';
use feature 'say';
use Encode qw(decode encode);
plugin 'RenderFile';

# OpenBSD promises.
my $openbsd = 0;
$openbsd = 1 if $^O eq "openbsd";
pledge("stdio cpath rpath wpath inet flock fattr") if $openbsd;

# 100 MBs

my $MAX_SIZE = 1024 * 1024 * 100;
my @BANNED = qw();			  # Add banned IP addresses here
my $RANDOMIZE_FILENAME = 0;   # Enable/disable randomization

my $dirname;
my $link;

mkdir "f";

# Function to handle file uploads

sub logger ( $level, $address, $message ) {
	open( my $fh, ">>", "sakisafe.log" );
	printf( $fh "[%s]: %s has uploaded file %s\n", $level, $address, $message );
	close($fh);
}

sub handle_file {
	my $c        = shift;
	my $filedata = $c->param("file");
	if ( $filedata->size > $MAX_SIZE ) {
		return $c->render(
					   text   => "Max upload size: $MAX_SIZE",
					   status => 400
					  );
	}
	if ( List::MoreUtils::any { /$c->tx->remote_address/ } uniq @BANNED ) {
		$c->render(
				 text =>
				 "Hi! Seems like the server admin added your IP address to the banned IP array."
				 . "As the developer of sakisafe, I can't do anything.",
				 status => 403
				);
		return;
	}

	# Generate random string for the directory
	my @chars = ( '0' .. '9', 'a' .. 'Z' );
	$dirname .= $chars[ rand @chars ] for 1 .. 5;
	my $filename = $filedata->filename;
	my $enc = encode( "UTF-8", $filename );
	$filename = $enc;
	if ( $RANDOMIZE_FILENAME == 1 ) {
		my $extension = $filename;
		$extension =~ s/.*\.//;
		$filename = "";
		$filename .= $chars[ rand @chars ] for 1 .. 5;
		$filename = $filename . "." . $extension;
	}
	carp( color("bold yellow"),
		 "sakisafe warning: could not create directory: $ERRNO",
		 color("reset") )
	  unless mkdir( "f/" . $dirname );
	$filename .= ".txt" if $filename eq "-";
    
	# TODO: get whether the server is http or https
	# There's a CGI ENV variable for that.
	my $host = $c->req->url->to_abs->host;
     my $ua = $c->req->headers->user_agent;
	$filedata->move_to( "f/" . $dirname . "/" . $filename );
	$link = "http://$host/f/$dirname/$filename";
	$c->stash(link => $link, host => $host, dirname => $dirname);
    

	$c->res->headers->header(
						'Location' => "$link" . $filename );

	# Only give the link to curl, html template for others.
	
	if($ua =~ m/curl/) {
		$c->render(
				 text => $link . "\n",
				 status => 201,
				);

		$dirname = "";
	} else {
		$c->render(
				 template => 'file',
				 status => 201,
				);
	}
	logger( "INFO", $c->tx->remote_address, $dirname . "/" . $filename );
	$dirname = "";
}

# Function to log uploaded files

get '/' => 'index';
post '/' => sub ($c) { handle_file($c) };

# Allow files to be downloaded.

get '/f/:dir/#name' => sub ($c) {
	my $dir  = $c->param("dir");
	my $file = $c->param("name");
	my $ext  = $file;
	$ext =~ s/.*\.//;
	my $path = "f/" . $dir . "/" . $file;

	#carp "sakisafe warning: could not get file: $ERRNO" unless
	$c->render( text => "file not found", status => 404 ) unless -e $path;
	$c->render_file(
				 filepath            => $path,
				 format              => $ext,
				 content_disposition => 'inline'
				);

}
;
app->max_request_size( 1024 * 1024 * 100 );

post '/upload' => sub ($c) { handle_file($c) };

app->start;

# Index template

#By default Mojolicious gets the "directory root" from the "public"
# directory, so the css and the favicon from the "public" directory,
# in the root of this repo.

# Not sure why I have to do this filthy hack, could not get Mojolicious
# to get the template here. So a TODO is to fix this.

__DATA__
@@ file.html.ep
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <title>sakisafe</title>
  <link rel="stylesheet" type="text/css" href="index.css"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  </head>
  <body>
  <center>
  <h1>sakisafe</h1>
  <h2>shitless file upload, pastebin and url shorter</h2>
  <img src="saki.png"/>
  <h2>LINK</h2>
  <code><%= $link %></code>
  </center>
  <p>Running sakisafe 2.4.0</p>
  </body>
  </html>

  __END__


@@ index.html.ep
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <title>sakisafe</title>
  <link rel="stylesheet" type="text/css" href="index.css"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  </head>
  <body>
  <center>
  <h1>sakisafe</h1>
  <h2>shitless file upload, pastebin and url shorter</h2>
  <img src="saki.png"/>
  <h2>USAGE</h2>
  <p>POST a file:</p>
  <code>curl -F 'file=@yourfile.png' https://<%= $c->req->url->to_abs->host; %></code>
  <p>Post your text directly</p>
  <code>curl -F 'file=@-' https://<%= $c->req->url->to_abs->host; %></code>
  </center>
  <p>Running sakisafe 2.4.0</p>
  <div class="left">
  <h2>Or just upload a file here</h2>
  <form ENCTYPE='multipart/form-data' method='post' action='/upload'>
  <input type='file' name='file' size='30'/>
  <input type='submit' value='upload'/>
  </form>
  </div>
  </body>
  </html>

