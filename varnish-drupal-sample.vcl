# A drupal varnish config file for varnish 3.x
#
# Will work with Drupal 7 and Pressflow 6.
#
# Default backend definition.  Set this to point to your content
# server. We are assuming you have a web server running on port 8080.
#

backend default {
  .host = "127.0.0.1";
  .port = "8000";
  .max_connections = 250;
  .connect_timeout = 300s;
  .first_byte_timeout = 300s;
  .between_bytes_timeout = 300s;
  .probe = {
    .url = "/";
    .timeout = 0.3s;
    .interval = 1s;
    .window = 10;
    .threshold = 8;
  }
}

acl purge {
 "localhost";
 "127.0.0.1";
}

#
sub vcl_recv {
  # Setup grace mode.
  # Allow Varnish to serve up stale (kept around) content if the backend is
  #responding slowly or is down.
  # We accept serving 6h old object (plus its ttl)
  if (! req.backend.healthy) {
   set req.grace = 6h;
  } else {
   set req.grace = 15s;
  }

  # If our backend is down, unset all cookies and serve pages from cache.
  if (!req.backend.healthy) {
    unset req.http.Cookie;
  }

  # If the request is to purge cached items, check if the visitor is authorized
  # to invoke it. Only IPs in 'purge' acl we defined earlier are allowed to
  # purge content from cache.
  # Return error 405 if the purge request comes from non-authorized IP.
  if (req.request == "PURGE") {
    if (!client.ip ~ purge) {
      # Return Error 405 if client IP not allowed.
      error 405 "Forbidden - Not allowed.";
    }
    return (lookup);
  }

  if (req.restarts == 0) {
    if (req.http.x-forwarded-for) {
      set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    }
    else {
      set req.http.X-Forwarded-For = client.ip;
    }
  }

  if (req.request != "GET" &&
      req.request != "HEAD" &&
      req.request != "PUT" &&
      req.request != "POST" &&
      req.request != "TRACE" &&
      req.request != "OPTIONS" &&
      req.request != "DELETE") {
      /* Non-RFC2616 or CONNECT which is weird. */
      return (pipe);
  }
  if (req.request != "GET" && req.request != "HEAD") {
      /* We only deal with GET and HEAD by default */
      return (pass);
  }

  # Always cache things with these extensions
  if (req.url ~ "\.(js|css|jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf)$") {
    return (lookup);
  }

  # Pass directly to backend (do not cache) requests for the following
  # paths/pages.
  # We tell Varnish not to cache Drupal edit or admin pages
  # Edit/Add paths that should never be cached according to your needs.
  if (req.url ~ "^/status\.php$"      ||
      req.url ~ "^/update\.php$"      ||
      req.url ~ "^/cron\.php$"        ||
      req.url ~ "^/install\.php$"     ||
      req.url ~ "^/ooyala/ping$"      ||
      req.url ~ "^/admin"             ||
      req.url ~ "^/admin/.*$"         ||
      req.url ~ "^/user"              ||
      req.url ~ "^/user/.*$"          ||
      req.url ~ "^/comment/reply/.*$" ||
      req.url ~ "^/login/.*$"         ||
      req.url ~ "^/login"             ||
      req.url ~ "^/node/.*/edit$"     ||
      req.url ~ "^/node/.*/edit"      ||
      req.url ~ "^/node/add/.*$"      ||
      req.url ~ "^/info/.*$"          ||
      req.url ~ "^/flag/.*$"          ||
      req.url ~ "^.*/server-status$"  ||
      req.url ~ "^.*/ajax/.*$"        ||
      req.url ~ "^.*/ahah/.*$") {
      return (pass);
  }

  # In some cases, i.e. when an editor uploads a file, it makes sense to pipe the
  # request directly to Apache for streaming.
  # Also, you should pipe the requests for very large files, i.e. downloads area.
  if (req.url ~ "^/admin/content/backup_migrate/export"     ||
      req.url ~ "^/admin/config/regional/translate/import"  ||
      req.url ~ "^/batch/.*$"                               ||
      req.url ~ "^/dls/.*$" ) {
      return (pipe);
  }

  # Remove all cookies for static files, images etc
  # Varnish will always cache the following file types and serve them (during TTL).
  # Note that Drupal .htaccess sets max-age=1209600 (2 weeks) for static files.
  if (req.url ~ "(?i)\.(bmp|png|gif|jpeg|jpg|doc|pdf|txt|ico|swf|css|js|html|htm)(\?[a-z0-9]+)?$") {
    // Remove the query string from static files
    set req.url = regsub(req.url, "\?.*$", "");

    unset req.http.Cookie;

    # Remove extra headers
    # We remove Vary and user-agent headers that any backend app may set
    # If we don't do this, Varnish will cache a separate copy of the resource
    # for every different user-agent
    unset req.http.User-Agent;
    unset req.http.Vary;

    return (lookup);
  }

  ## Remove has_js, toolbar collapsed and Google Analytics cookies.
  set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(__[a-z]+|has_js|Drupal.toolbar.collapsed|Drupal.tableDrag.showWeight)=[^;]*", "");

  ## Remove a ";" prefix, if present.
  set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

  ## Remove empty cookies.
  if (req.http.Cookie ~ "^\s*$") {
    unset req.http.Cookie;
  }

  ## fix compression per http://www.varnish-cache.org/trac/wiki/FAQ/Compression
  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
      # No point in compressing these
      remove req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
      set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate" && req.http.user-agent !~ "MSIE") {
      set req.http.Accept-Encoding = "deflate";
    } else {
      # unkown algorithm
      remove req.http.Accept-Encoding;
    }
  }

  # If they still have any cookies, do not cache.
  if (req.http.Authorization || req.http.Cookie) {
    /* Not cacheable by default */
    return (pass);
  }

  # Don't cache Drupal logged-in user sessions
  # LOGGED_IN is the cookie that earlier version of Pressflow sets
  # VARNISH is the cookie which the varnish.module sets
  if (req.http.Cookie ~ "(VARNISH|DRUPAL_UID|LOGGED_IN)") {
    return (pass);
  }
  return (lookup);
}

sub vcl_hash {
  hash_data(req.url);
  if (req.http.host) {
    hash_data(req.http.host);
  } else {
    hash_data(server.ip);
  }
  return (hash);
}

sub vcl_fetch {
  # Don't allow static files to set cookies.
  if (req.url ~ "(?i)\.(bmp|png|gif|jpeg|jpg|doc|pdf|txt|ico|swf|css|js|html|htm)(\?[a-z0-9]+)?$") {
    unset beresp.http.set-cookie;
    # default in Drupal, you may comment out to apply for other cms as well
    #set beresp.ttl = 2w;
  }
  if (beresp.status == 301) {
    set beresp.ttl = 1h;
    return(deliver);
  }

  # Allow items to be stale if backend goes down. This means we keep around all
  # objects for 6 hours beyond their TTL which is 2 minutes So after 6h + 2 minutes
  # each object is definitely removed from cache
  set beresp.grace = 6h;

  # If you need to explicitly set default TTL, do it below.
  # Otherwise, Varnish will set the default TTL by looking-up
  # the Cache-Control headers returned by the backend
  # set beresp.ttl = 6h;
}

sub vcl_hit {
  if (req.request == "PURGE") {
    purge;
    error 200 "Purged.";
  }
}

sub vcl_miss {
  if (req.request == "PURGE") {
    purge;
    error 200 "Purged.";
  }
}

sub vcl_deliver {
  # From http://varnish-cache.org/wiki/VCLExampleLongerCaching
  if (resp.http.magicmarker) {
    /* Remove the magic marker */
    unset resp.http.magicmarker;

    /* By definition we have a fresh object */
    set resp.http.age = "0";
  }

  #add cache hit data
  if (obj.hits > 0) {
    #if hit add hit count
    set resp.http.X-Varnish-Cache = "HIT";
    set resp.http.X-Varnish-Cache-Hits = obj.hits;
  }
  else {
    set resp.http.X-Varnish-Cache = "MISS";
  }
  return (deliver);
}