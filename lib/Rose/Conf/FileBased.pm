package Rose::Conf::FileBased;

use strict;

use Carp();
use File::Spec;

use Rose::Conf;
require Tie::Hash;
our @ISA = qw(Rose::Conf Tie::StdHash);

our($CONF_ROOT, %Refresh_Time, $APACHE_CONF_PATH);

our $REFRESH_TIMEOUT = 60 * 15; # in seconds

our $CONF_SUFFIX     = '.conf';
our $LOCAL_CONF_FILE = 'local' . $CONF_SUFFIX;

use constant PRIVATE_PREFIX => '__' . __PACKAGE__ . '::';

our $VERSION = '0.01';

our $Debug = 0;

sub import
{
  my($class) = shift;

  local $Rose::Conf::ExportLevel;
  $Rose::Conf::ExportLevel++;

  $class->Rose::Conf::import(@_)  if(@_);

  my $conf = $class->conf_hash;

  my %save = %$conf;

  tie(%$conf, $class);

  %$conf = %save;
}

sub refresh
{
  my($class) = shift;

  #return  if(time < $Refresh_Time{$class} + $class->refresh_timeout);

  $class->_get_conf_root();

  if($CONF_ROOT && -d $CONF_ROOT)
  {
    #$Refresh_Time{$class} ||= 0;

    # Local conf file
    my $local_conf = File::Spec->catfile($CONF_ROOT, $LOCAL_CONF_FILE);

    if(-s $local_conf)
    {
      $class->_read_combined_conf($local_conf);
    }

    # Package-specific conf file
    my $class_conf = File::Spec->catfile($CONF_ROOT, $class . $CONF_SUFFIX);

    if(-s $class_conf)
    {
      $class->_read_class_conf($class_conf);
    }
    else
    {
      my $mod_class = $class;
      $mod_class =~ s/::/-/g;

      $class_conf = $CONF_ROOT . '/' . $mod_class . $CONF_SUFFIX;

      if(-s $class_conf)
      {
        $class->_read_class_conf($class_conf);
      }
    }
  }
}

sub FETCH
{
  my($hash, $key) = @_;

  unless(exists $hash->{PRIVATE_PREFIX . 'IMPORTED'} || 
         exists $hash->{PRIVATE_PREFIX . 'IMPORTING'})
  {
    $Debug && warn "FETCH $hash { $key }\n";

    $hash->{PRIVATE_PREFIX . 'IMPORTING'} = 1;

    my $class = ref($hash);

    $class->refresh();

    delete $hash->{PRIVATE_PREFIX . 'IMPORTING'};

    $hash->{PRIVATE_PREFIX . 'IMPORTED'}++;
  }

  ##
  ## This is broken for now...
  ##

  # Do not try refresh when looking up private keys
#   unless(index($key, PRIVATE_PREFIX) == 0)
#   {
#     my $class = ref $hash;
# 
#     if(my $timeout = $class->refresh_timeout)
#     {
#       $Refresh_Time{$class} ||= 0;
#  
#       if(time > $Refresh_Time{$class} + $timeout)
#       {
#         $class->refresh;
#       }
#     }
#   }

  Carp::croak "No such conf parameter: '$key'\n"
    unless(index($key, PRIVATE_PREFIX) == 0 || exists $hash->{$key});

  return $hash->{$key};
}

sub _get_conf_root
{
  $CONF_ROOT = $ENV{'ROSE_CONF_FILE_ROOT'};

  if(!$CONF_ROOT && exists $ENV{'MOD_PERL'} && require mod_perl && $mod_perl::VERSION < 1.99)
  {
    $CONF_ROOT = Apache->server_root_relative($APACHE_CONF_PATH);
    $CONF_ROOT = undef  unless(-d $CONF_ROOT);
  }
}

sub refresh_timeout
{
  my($class) = shift;

  no strict 'refs';

  if(@_)
  {
    return ${$class . '::REFRESH_TIMEOUT'} = shift;
  }

  my $timeout = ${$class . '::REFRESH_TIMEOUT'};

  $timeout = $REFRESH_TIMEOUT  unless(defined $timeout);

  return $timeout;
}

sub _parse_line
{
  my($class, $conf, $line, $file, $line_num) = @_;

  return  unless($line =~ /\S/);

  my($key, $val);

  if($line =~ /^(\w+)\s*=\s*(\S.*|$)/)
  {
    $key = $1;
    $val = $2;
  }
  elsif($line !~ /^(#|$)/)
  {
    die "Syntax error in $file on line $line_num: $line\n";
  }
  else { return }

  if(length($key) && length($val))
  {
    $val =~ s/(['"])(.*)\1$/$2/;     

    $Debug && warn "\$${class}::CONF{$key} = $val\n";

    $conf->{$key} = $val;

    #if($@)
    #{
    #  die qq(Invalid value "$val" in $file on line $line_num: $@\n);
    #}
  }
  else
  {
    $Debug && warn "\$${class}::CONF{$key} = undef\n";
    $conf->{$key} = undef;
  }

  $conf->{PRIVATE_PREFIX . 'MODIFIED'}{$key} =
  {
    file        => $file,
    line_number => $line_num,
    #time        => time(),
  };
}

sub _read_class_conf
{
  my($class, $file) = @_;

  unless(open(CONF, $file))
  {
    warn "Could not open $file: $!";
    return;
  }

  #$Refresh_Time{$class} = time;

  my $conf = $class->conf_hash;

  while(<CONF>)
  {
    s/^\s+//;
    s/\s+$//;

    $class->_parse_line($conf, $_, $file, $.);
  }

  close(CONF);
}

sub _read_combined_conf
{
  my($class, $file) = @_;

  my $conf_fh;

  unless(open($conf_fh, $file))
  {
    warn "Could not open $file: $!";
    return;
  }

  #$Refresh_Time{$class} = time;

  my $conf = $class->conf_hash;

  my $in_domain = 0;

  my $in_domain_re  = qr(^CLASS\s+$class$);
  my $out_domain_re = qr(^CLASS\s*(?!=));

  while(<$conf_fh>)
  {
    s/^\s+//;
    s/\s+$//;

    if(/$in_domain_re/)
    {
      $in_domain = 1;
      next;
    }
    elsif($in_domain && /$out_domain_re/)
    {
      $in_domain = 0;
    }

    next  unless($in_domain);

    $class->_parse_line($conf, $_, $file, $.);
  }

  close($conf_fh);
}

sub local_conf_keys
{
  my($class) = shift;

  my $conf = $class->conf_hash;

  return keys(%{$conf->{PRIVATE_PREFIX . 'MODIFIED'}});
}

sub local_conf_setting
{
  my($class, $key) = @_;

  Carp::croak "Cannot get setting without $key"  unless(defined($key));

  my $conf = $class->conf_hash;

  return  unless($conf->{PRIVATE_PREFIX . 'MODIFIED'}{$key});

  return bless($conf->{PRIVATE_PREFIX . 'MODIFIED'}{$key}, 'Rose::Conf::File::Setting');  
}

sub local_conf_value
{
  my($class, $key) = @_;

  Carp::croak "Cannot get setting without $key"  unless(defined($key));  

  $class->local_conf_setting($key) || return undef;

  return $class->param($key);
}

BEGIN
{
  $APACHE_CONF_PATH = 'conf/perl';

  #_get_conf_root();

  require Rose::Object;
  @Rose::Conf::File::Setting::ISA = qw(Rose::Object);
}

1;

# =item B<refresh_timeout SECS>
# 
# If an argument is provided, sets the class's refresh timeout to SECS
# seconds.  Returns the class's current refresh timeout in seconds.
# 
# The refresh timeout is used to determine when (if ever) to refresh the
# configuration hash by re-reading the (possibly changed) configuration
# file(s).  The configuration file(s) will only be re-read if they have
# been modified since they were last read (as determined by the files'
# "mtime").
# 
# If the refresh timeout is zero, the files are never re-read.  The
# default refresh timeout is 15 minutes.

__END__

=head1 NAME

Rose::Conf::FileBased - File-based configuration module base class.

=head1 SYNOPSIS

    # File: My/System/Conf.pm
    package My::System::Conf;

    use Rose::Conf::FileBased;

    our @ISA = qw(Rose::Conf::FileBased);

    our %CONF = 
    (
      KEY1 => 'value1',
      KEY2 => 'value2',
      ...
    );
    ...


    # File: My/System.pm
    use My::System::Conf qw(%SYS_CONF); # import hash
    ...


    # File: My/System/Foo.pm
    use My::System::Conf; # do not import hash
    ...


    # File: $ENV{'ROSE_CONF_FILE_ROOT'}/local.conf
    CLASS My::System::Conf
    KEY1 = "new value"
    KEY2 = "new two"
    ...


    # File: $ENV{'ROSE_CONF_FILE_ROOT'}/My::System::Conf.conf
    KEY1 = "the final value"
    ...


    # File: somefile.pl
    use My::System::Conf qw(%SYS_CONF);

    print $SYS_CONF{'KEY1'}; # prints "the final value"
    print $SYS_CONF{'KEY2'}; # prints "new two"

=head1 DESCRIPTION

C<Rose::Conf::FileBased> inherits from C<Rose::Conf> and provides the same
functionality, with the additional ability to read and incorporate text
configuration files which override the values hard-coded into the
configuration module.

Text configuration files must be located in the file-based configuration file
root ("conf root") directory. This directory is set as follows:

If the environment variable C<ROSE_CONF_FILE_ROOT> exists, it is used to set
the conf root.  The C<Rose::Conf::Root> module is the recommended way to set
this environment variable from within Perl code.  Setting thee environment
variable directly from within Perl code may become unsupported at some point
in the future.

If C<ROSE_CONF_FILE_ROOT> is not set and if running in a mod_perl 1.x
environment, the conf root is set to the "conf/perl" directory relative to the
web server's "server root" directory. That is:

    Apache->server_root_relative('conf/perl')

If no conf root is defined, C<Rose::Conf::FileBased> behaves like C<Rose::Conf>,
except that trying to access a nonexistent parameter name through a hash alias
or reference to the conf hash results in a fatal error.

=head1 CONFIGURATION FILES

There are two types of configuration files: "combined" and "class-specific."
As described above, all configuration files must be stored in the "conf root"
directory.  In cases of conflict, entries in a "class-specific" configuration
file override entries in a "combined" configuration file.

=head2 THE "COMBINED" CONFIGURATION FILE

The "combined" configuration file must be named "local.conf".  This file name
is case sensitive. The format of the "local.conf" file is as follows:

    CLASS Some::Package::Conf
    KEY1 = "value1"
    KEY2 = 'value2'
    KEY3 = 5

    # This is a comment

    CLASS Some::Other::Package::Conf
    KEY1 = "value1"
    KEY2 = 'value2'
    KEY3 = 5

The C<CLASS> directive sets the context for all the key/value pairs that
follow it.  The C<KEY>s are keys in C<CLASS>'s C<%CONF> hash.

Values may or may not be enclosed in quotes.  Only simple scalar values are
supported at this time, and the values must be on one line. Blank lines,
lines that begin with the comment character "#", and leading and trailing
spaces are ignored.


=head2 "CLASS-SPECIFIC" CONFIGURATION FILES

"Class-specific" configurations file must have a name equal to the
concatenation of the configuration package name and ".conf".  For example, the
class-specific configuration file for the C<My::Class::Conf> package would be
"My::Class::Conf.conf".  This file name is case sensitive.

If your operating system or volume format does not allow ":" characters in
file names, you can use "-" instead: "My-Class-Conf.conf"

The format of each class-specific configuration file is as follows:

    # This is a comment

    KEY1 = "value1"
    KEY2 = 'value2'
    KEY3 = 5

The C<KEY>s are keys into the class's C<%CONF> hash.  Values may or may
not be enclosed in quotes.  Only simple scalar values are supported at
this time, and the values must be on one line.  Blank lines, lines that
begin with the comment character "#", and leading and trailing spaces
are ignored.

=head1 COMPLEX VALUES

Lists, hashes, and other values that are not simple scalars may be supported
in the future. For now, if you need to include such values, it's a simple
matter to add code to "inflate" the values as necessary. Example:

    # File: local.conf
    CLASS My::Conf

    # Scalar value will be expanded into an array ref later
    NAMES = 'Tom,Dick,Harry'
    ...


    # File: My/Conf.pm
    package My::Conf;

    use Rose::Conf::FileBased;
    our @ISA = qw(Rose::Conf::FileBased);

    our %CONF =
    (
      COLOR => 'blue',
      NAMES => [ 'Sue', 'Joe', 'Pam' ],
    );

    # Override refresh method and auto-expand non-scalar values
    # according to whatever format or convention we choose
    sub refresh
    {
      shift->SUPER::refresh(@_);

      # Expects a string of comma-separated values,
      # then expands it into an array reference
      $CONF{'NAMES'} = [ split(',', $CONF{'NAMES'}) ]
        unless(ref $CONF{'NAMES'});
    }
    ...


    # Some other code somewhere...
    use My::Conf;

    $names = My::Conf->param('NAMES');
    print join(' ', @$names); # 'Tom Dick Harry'

=head1 CLASS METHODS

Unless overridden below, all of C<Rose::Conf>'s class methods are inherited
by C<Rose::Conf::FileBased>.

=over 4

=item B<local_conf_keys>

Returns an unsorted list of configuration keys whose values have been set or
overridden by one or more configuration files.

=item B<local_conf_value KEY>

Returns the value of the configuration setting C<KEY> if and only if C<KEY>'s
value has been set or overridden by a configuration file.  Returns false
otherwise.

=item B<refresh>

Refreshes the configuration values in the class by re-reading any
configuration files.

=back

=head1 AUTHOR

John C. Siracusa (siracusa@mindspring.com)

=head1 COPYRIGHT

Copyright (c) 2004 by John C. Siracusa.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the same terms
as Perl itself.
