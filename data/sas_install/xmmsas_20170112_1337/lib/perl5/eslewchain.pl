#! /usr/bin/perl -w
#
# eslewchain
#
# Cuts a slew into a series of images
#
# Author: Richard Saxton (richard.saxton@sciops.esa.int)
#
# Description:
#
# This SAS task takes the event file from a slew and cuts it into
# a sequence of images of roughly 1 x 0.5 degrees in size. It calculates
# the attitude from a Raw Attitude File (RAF) which must reside in a
# directory pointed to by $SAS_ODF.
#
# The current version produces images in the bands
# This is a pipeline version which uses the energy bands
#
# 8 - PI=200-12000
# 7 - PI=2000-12000
# 6 - PI-200-2000
#
# Version 1.4 - 02/2/2010  
# Version 1.6 - 31/7/2014  - updates for xmmsl2
# Version 1.7 - 11/8/2015  - optionally produces .png files
#
# NB: The task makes significant use of the ftools utilities. 
#
# Needs:
#  SAS_ODF must point to a directory containing the attitude files 
#  for this slew.
#  The current directory must contain an event file produced by 
#  odfingest and epproc 
#
use POSIX qw(ceil floor);
use SAS;
use strict;

# Define task
my $TASK_NAME="eslewchain";   #
my $TASK_VERSION="1.7";   #

# Handle command line params -v, -p -,h
#if ( grep /^--?v/, @ARGV) { getVersion() ; exit; } ;
#if ( grep /^--?p/, @ARGV) { showSyntax() ; exit; } ;
#if ( grep /^--?h/, @ARGV) { showSyntax() ; exit; } ;

# Define status variable
my $status=0;

sub eslewchain
{

# Set SAS_ATTITUDE = RAF
# Issue a warning if SAS_ATTITUDE is not set to RAF
if ( not exists $ENV{'SAS_ATTITUDE'} or $ENV{'SAS_ATTITUDE'} ne 'RAF' )
   { SAS::warning("UseRAF", "the SAS_ATTITUDE environment variable should be set to RAF when processing slew data") }

# Read in the event filename
#    my $evfile = stringParameter("table");

# Check that SAS_ODF is set
    if ( !exists $ENV{'SAS_ODF'}) 
            {SAS::error("odf", "SAS_ODF not set to a valid directory")}

# Find the name of the event file in the current directory
    my $evf = 0; my $evfile = "";
    ##open(FILST, "ls $indir/*EVL* $indir/*ImagingEvts* |");
    ##open(FILST, "ls *EVL* *ImagingEvts* |");
    opendir(CDIR,".");
    while ( my $fname = readdir(CDIR) ) {
      if ( $fname =~ /EVL/ or $fname =~ /Imag/ ) {
         chomp($evfile = $fname);
         $evf = $evf + 1;
      }
    }
    if ( $evf == 0 )
      { SAS::error("evfile", "No event file found in current directory")}
    elsif ( $evf > 1) 
      { SAS::error("evfile", "More than one event file found in current directory")}
    else 
      { print "Using event file: $evfile\n"};

# To avoid messy processing - refuse to run on slews with missing exposure extn
    checkExpExtns($evfile);
 
# Find the rough start position of the slew 
# and check that the ftools are set-up ok
    my $nomra=getKeyWord($evfile, 'RA_PNT');
    my $nomdec=getKeyWord($evfile, 'DEC_PNT');
    my $nompa=getKeyWord($evfile, 'PA_PNT');

# Find the start and stop time of the first slew frame in s/c time units
    my $evfblk1 = $evfile . "+1";
    my $slew_start=getKeyWord($evfblk1, 'TSTART');
    my $slew_stop=getKeyWord($evfblk1, 'TSTOP');

print "RA: $nomra DEC: $nomdec PA: $nompa START: $slew_start\n";
#exit
#
# Run atthkgen to produce an ATTITUDE file - this is used to get the
# pointing RA_PNT, DEC_PNT info. 
#
    my $c_atthkgen = "atthkgen atthkset=atthk.dat";

#    SAS::message($SAS::AppMsg,$SAS::VerboseMsg,"$c_atthkgen");
    runtask($c_atthkgen);

# Set the attitude relative to the slew start position
    my $c_attcalc = "attcalc eventset=\"$evfile\" imagesize=200.0 "; 
    $c_attcalc   .= "refpointlabel=user nominalra=\"$nomra\" ";
    $c_attcalc   .= "nominaldec=\"$nomdec\" withatthkset=no ";

#    SAS::message($SAS::AppMsg,$SAS::VerboseMsg,"$c_attcalc");
    runtask($c_attcalc);

# Find the X and Y pixel ranges
    my @ranges = findminmaxxy($evfile);
   print "MINMAX: $ranges[0] $ranges[1] $ranges[2] $ranges[3]"; 
    my $xdiff = $ranges[1] - $ranges[0];
    my $ydiff = $ranges[3] - $ranges[2];

# Find the observation number and remove quotes
    my $obs=getKeyWord($evfile, 'OBS_ID');
    $obs =~ s/'//g;

# Split the slew into small event files and make images
# depending on whether the slew is predominantly in the X or Y direction
    if ( $ydiff > $xdiff ) 
      { slewsplit($obs, $evfile, "Y", $slew_start, $slew_stop) }
    else
      { slewsplit($obs, $evfile, "X", $slew_start, $slew_stop) }

# Rename and Clean
    RenameAndClean($obs, $evfile);

# Sayanora
print "eslewchain processing finished\n";

}
# end eslewchain


# ------------------------------------------------------
# runtask - runs a task and handles the return status 
# ------------------------------------------------------
sub runtask{
   my $taskname=$_[0];
   system("$taskname");
   if ($? != 0) {
#       SAS::fatal("TaskFailed","$taskname returned error $?");
       print "error in  $taskname \n";
   }
}


sub findminmaxxy{

# pget seems to be unreliable so we manipulate text output from fstatistic
# to get the results

   my $evfile=$_[0];

   my @minmax;

   my $tmpfile = 'del_fstat';

   system("fstatistic infile=$evfile colname='X' rows='-' outfile=$tmpfile clobber=yes") == 0 or SAS::error("NoFtools","Couldn't run fstatistic");

   $minmax[0] = getlastnum($tmpfile, "minimum");
   $minmax[1] = getlastnum($tmpfile, "maximum");

   system("fstatistic infile=$evfile colname='Y' rows='-' outfile=$tmpfile clobber=yes");

   $minmax[2] = getlastnum($tmpfile, "minimum");
   $minmax[3] = getlastnum($tmpfile, "maximum");

 # Clean up
   system("rm $tmpfile ") ==0
         or SAS::error("NoClean","Failed to remove temporary file");

   return @minmax;
}

sub getKeyWord{

# Use fkeyprint to get a keyword from a file
    my $infile=$_[0];
    my $keyword=$_[1];
    my $value;

# Add a +0 to denote the first extension if extension has not been included
    if (index($infile, "+") == -1) { $infile = $_[0] . "+0";}

    my $tmpfile = 'del_keyword';
    
    if(system("fkeyprint infile=$infile keynam=$keyword outfile=$tmpfile clobber=yes")){
             SAS::fatal("ErrFkeypar","Cannot run ftools task fkeyprint");
    }

    open (TMPFILE, "<$tmpfile") or die (" Can't open file $!\n");

#  Loop over each line
    while (my $line = <TMPFILE>) {
     if ( ($line =~ /$keyword/) && ($line =~ "=") ) {
          my (@list) = split "=", $line;
          my (@list2) = split " ", $list[1];

          $value= $list2[0]; 
     }
    }
    close TMPFILE;

  # Remove the temporary file
    system("rm $tmpfile") ==0
         or SAS::error("NoClean","Failed to remove temporary file");

    return $value;
}

# numevents
#
# Purpose: Find the number of events in an event file
#
sub numevents{

   my $evfile=$_[0]."[EVENTS]";
   print "$evfile\n";

   my $numevents;

   system("fstruct infile=$evfile outfile=STDOUT") == 0 or
           SAS::error("NoFtools","Couldn't run fstatistic");
   chomp($numevents=`pget fstruct naxis2`);

   print "Found $numevents events\n";

   return $numevents;
}

# 
# getlastnum
#
# Purpose: Finds a number from the last element in a text line
#
sub getlastnum {

  my $tmpfile=$_[0];
  my $srchstring=$_[1];
  my $number;
 
  open (TMPFILE, "<$tmpfile") or die (" Can't open file $!\n");

#  Loop over each line
  while (my $line = <TMPFILE>) {
#     chomp $line;
     if ( $line =~ /$srchstring/ ) {
          my (@list) = split " ", $line;
          $number = $list[$#list]; 
     }
   }
   close TMPFILE;

   return $number;
}

#
# slewsplit
#
# Does the splitting of a slew into small images
#
sub slewsplit {

# Open the input event file
my $obs=$_[0];
my $infile=$_[1];

# Find out if .png files are wanted
my $makepng = getMakePngParam();

print "Making png files: $makepng\n";

# Find the range of times of the events in the full file - roughly equivalent
# to the start and end time of the exposure in the subimage
my $line = findtimerange($infile);
my (@list) = split " ", $line;
my $tbegin= $list[0];
my $tend = $list[1];

# Work out the number of subimages
my $tdelta = 45.0;
my $nmaps = ceil(($tend - $tbegin) / $tdelta);

# Find the range of X and Y values in the event file
my @xylist = findminmaxxy($infile);
my $xmin = $xylist[0];
my $xmax = $xylist[1];
my $ymin = $xylist[2];
my $ymax = $xylist[3];

# The hack to start from a given position
#$ymin=$ybegin;

print "Original sky coord ranges: $xmin $xmax $ymin $ymax\n";
print "Original time range: $tbegin $tend\n";

# Loop over the input file extracting roughly 1 degree square fields
print "No of images to create: $nmaps\n";

# Make the root filenames
my $outroot = "P" . $obs . "PNS003IMAGE_";
my $exproot = "P" . $obs . "PNS003EXPMAP";
my $unfroot = "P" . $obs . "PNS003UNFDAT";

# Define temp files
my $timfiltfile = 'timefiltfile.ds';
my $largetimfiltfile = 'largetimefiltfile.ds';

# Initialise an image count
my $imcount=0;
my @args; 
# my $line; my @list; # Careful with this reuse !

# Loop over each subimage
for (my $j = 0; $j < $nmaps; $j++) {

# Find the time range for this subimage
   my $tstart = $tbegin + $j * $tdelta;
   my $tstop = $tstart + $tdelta;

  # Sort out the filename stems for this image count - image numbers in HEX.
   my $imcstring = sprintf "%003x", $imcount;
   my $filtfile = "P" . $obs . "PNS003PIEVLI0" . $imcstring . ".ds";

  # Select events during this time range +/- the delta
   my $tstart_extra = $tstart - $tdelta;
   my $tstop_extra = $tstop + $tdelta;
   @args = ("evselect","table=$infile","expression=(TIME in [$tstart_extra:$tstop_extra])","filtertype=expression","writedss=yes","destruct=yes", "filteredset=$largetimfiltfile","withfilteredset=yes","keepfilteroutput=yes", "ximagebinsize=55","yimagebinsize=55","ximagemin=1","ximagemax=640","withxranges=no","yimagemin=1","yimagemax=640","withyranges=no","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "event file filtering failed for $tstart $tstop";
  
  # attcalc this large file
   rejig_attitude($largetimfiltfile);

  # extra a new file with just the inner times
   @args = ("evselect","table=$largetimfiltfile","expression=(TIME in [$tstart:$tstop])","filtertype=expression","writedss=yes","destruct=yes", "filteredset=$timfiltfile","withfilteredset=yes","keepfilteroutput=yes", "ximagebinsize=55","yimagebinsize=55","ximagemin=1","ximagemax=640","withxranges=no","yimagemin=1","yimagemax=640","withyranges=no","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "event file filtering failed for $tstart $tstop";

  # If no events were found, skip to the next subimage
   if (numevents($timfiltfile) == 0) {next;}

  # Find the X and Y range for these times
   #my @xylist = findminmaxxy($timfiltfile);
   @xylist = findminmaxxy($timfiltfile);
   my $x1 = $xylist[0];
   my $x2 = $xylist[1];
   my $y1 = $xylist[2];
   my $y2 = $xylist[3];

   print "Using times: $tstart $tstop X: $x1 $x2 Y: $y1 $y2 \n";

  # Extract another event file with these X,Y ranges
     @args = ("evselect","table=$largetimfiltfile","expression=(X in [$x1:$x2])&&(Y in [$y1:$y2])","filtertype=expression","writedss=yes","destruct=yes", "filteredset=$filtfile","withfilteredset=yes","keepfilteroutput=yes", "ximagebinsize=55","yimagebinsize=55","ximagemin=1","ximagemax=640","withxranges=no","yimagemin=1","yimagemax=640","withyranges=no","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

     system(@args) ==0
         or print "event file filtering failed for $x1 $y1";

  # Reconstruct the attitude for this events subfile
   ## NOT NEEDED NOW ??    
   rejig_attitude($filtfile);

  # Find the new X,Y range
   my @xylist = findminmaxxy($filtfile);
   my $xminnew = $xylist[0];
   my $xmaxnew = $xylist[1];
   my $yminnew = $xylist[2];
   my $ymaxnew = $xylist[3];

   print "NEW range: $xminnew,$xmaxnew,$yminnew,$ymaxnew\n";

  # Get the RA and DEC of the centre from the filtfile
   $line = findcelcent($filtfile);
   (@list) = split " ", $line;
   my $ra = $list[0];
   my $dec = $list[1];
   my $rev = $list[2];

   my $outb1 = $outroot . "1" . $imcstring. ".ds";
   my $outb2 = $outroot . "2" . $imcstring. ".ds";
   my $outb3 = $outroot . "3" . $imcstring. ".ds";
   my $outb6 = $outroot . "6" . $imcstring. ".ds";  # Soft band image
   my $outb7 = $outroot . "7" . $imcstring. ".ds";  # hard band image
   my $outb8 = $outroot . "8" . $imcstring. ".ds";  # Total band image
   my $outbW = $unfroot . "8" . $imcstring. ".ds";  # Warts n all image

   my $expb1 = $exproot . "1" . $imcstring. ".ds";
   my $expb2 = $exproot . "2" . $imcstring. ".ds";
   my $expb3 = $exproot . "3" . $imcstring. ".ds";
   my $expb6 = $exproot . "6" . $imcstring. ".ds";
   my $expb7 = $exproot . "7" . $imcstring. ".ds";
   my $expb8 = $exproot . "8" . $imcstring. ".ds";

  # Create an image in each band from this events file

  # First create an image with no pattern, flag or PI selection to
  # serve as a diagnostic
   @args = ("evselect","table=$filtfile","expression=true","filtertype=expression","writedss=yes","xcolumn=X","ycolumn=Y","ximagebinsize=82","yimagebinsize=82","squarepixels=yes","imageset=$outbW","imagebinning=binSize","withimageset=yes","ximagemin=$xminnew","ximagemax=$xmaxnew","withxranges=yes","yimagemin=$yminnew","yimagemax=$ymaxnew","withyranges=yes","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "image creation failed for $x1 $y1";

  # 0.2-0.5 keV, patt 0
   @args = ("evselect","table=$filtfile","filtertype=expression","expression=(FLAG==0)&&(PI in [200:500])&&(PATTERN==0)","writedss=yes","xcolumn=X","ycolumn=Y","ximagebinsize=82","yimagebinsize=82","squarepixels=yes","imageset=$outb1","imagebinning=binSize","withimageset=yes","ximagemin=$xminnew","ximagemax=$xmaxnew","withxranges=yes","yimagemin=$yminnew","yimagemax=$ymaxnew","withyranges=yes","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "image creation failed for $x1 $y1";

  # 0.5-1.0 keV, patt 0-4
   @args = ("evselect","table=$filtfile","filtertype=expression","expression=(FLAG==0)&&(PI in [501:1000])&&(PATTERN<=4)","writedss=yes","xcolumn=X","ycolumn=Y","ximagebinsize=82","yimagebinsize=82","squarepixels=yes","imageset=$outb2","imagebinning=binSize","withimageset=yes","ximagemin=$xminnew","ximagemax=$xmaxnew","withxranges=yes","yimagemin=$yminnew","yimagemax=$ymaxnew","withyranges=yes","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "image creation failed for $x1 $y1";

  # 1.0-2.0 keV, patt 0-4
   @args = ("evselect","table=$filtfile","filtertype=expression","expression=(FLAG==0)&&(PI in [1001:2000])&&(PATTERN<=4)","writedss=yes","xcolumn=X","ycolumn=Y","ximagebinsize=82","yimagebinsize=82","squarepixels=yes","imageset=$outb3","imagebinning=binSize","withimageset=yes","ximagemin=$xminnew","ximagemax=$xmaxnew","withxranges=yes","yimagemin=$yminnew","yimagemax=$ymaxnew","withyranges=yes","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "image creation failed for $x1 $y1";

  # 2.0-12.0 keV, patt 0-4
   @args = ("evselect","table=$filtfile","filtertype=expression","expression=(FLAG==0)&&(PI in [2001:12000])&&(PATTERN<=4)","writedss=yes","xcolumn=X","ycolumn=Y","ximagebinsize=82","yimagebinsize=82","squarepixels=yes","imageset=$outb7","imagebinning=binSize","withimageset=yes","ximagemin=$xminnew","ximagemax=$xmaxnew","withxranges=yes","yimagemin=$yminnew","yimagemax=$ymaxnew","withyranges=yes","raimagecenter=0","decimagecenter=0","withcelestialcenter=no","timemin=0","timemax=1000","withtimeranges=no","maketimecolumn=no","makeratecolumn=no","withrateset=no","histogrammin=0","histogrammax=1000","withhistoranges=no");

   system(@args) ==0
         or print "image creation failed for $x1 $y1";

  # Find the range of times of the events in the full file - roughly equivalent
  # to the start and end time of the exposure in the subimage
   my $tstartMjd = MRTtoMJD($tstart);
   my $tstopMjd = MRTtoMJD($tstop);

  # Make the exposure maps
   atthkchop($filtfile);                # cut attitude file down to minimum

    #system(@args) ==0
         #or print "atthkchop failed for $xstart $ystart";
  
  # Save the image to a temporary file without a '+' sign
   @args = ("cp","$outb1","Idel.fits");
     system(@args) ==0
         or print "Failed to copy $outb1 to temporary file Idel.fits";

  # Create the exposure maps - based on attitude from temp att file
   @args = ("eexpmap","imageset=Idel.fits","attitudeset=temp_sp_atthk_chopped.dat","eventset=$filtfile","expimageset=$expb7 $expb6 $expb8","pimin=2000 200 200","pimax=12000 2000 12000","attrebin=1");
    system(@args) ==0
         or print "Exposure map creation failed for $x1 $y1";

  # Remove the temporary files
     system("rm Idel.fits temp_sp_atthk_chopped.dat") ==0
         or SAS::error("NoClean","Failed to remove temporary file");

  # Add together 0.2-0.5, 0.5-1.0, 1.0-2.0 and 2-12 keV images to
  # make the b8 and b6 images
    @args = ("farith","$outb1","$outb2","temp_sp_Itemp.ds","+","clobber=yes");
    system(@args);
    @args = ("farith","temp_sp_Itemp.ds","$outb3","$outb6","+","clobber=yes");
    system(@args);
    @args = ("farith","$outb6","$outb7","$outb8","+","clobber=yes");
    system(@args)  ==0 or print "Error combining images with farith";

  # Add standard slew keywords into output file headers
  # Make an array of final output filenames
    addSlewKeys($outb6,$outb7,$outb8,$expb6,$expb7,$expb8,$tstartMjd,$tstopMjd);

  # Make .pngs if requested
    if ($makepng) { make_png_files($outb6,$outb7,$outb8); }

  # Remove the EXPOSURE extensions from the filtered event file
    delete_exposure_xtns($filtfile);

  # Increment the image count
    $imcount++;

 } # End of loop over subimages

# Delete temporary files
 system("rm $timfiltfile temp_sp_Itemp.ds") ==0
         or SAS::error("NoClean","Failed to remove temporary files");
}


# 
# Finds the ranges in X which correspond to a degree of Y events
# or the ranges in Y which correspond to a degree of X
sub findranges{

# This routine makes an unnecessary use of temporary files - fix when 
# we get the chance
#
# Read in arguments
my $infile=$_[0];
my $outfile=$_[1];
my $xstart=$_[2];
my $xstop=$_[3];
my $ystart=$_[4];
my $ystop=$_[5];
my $dircn=$_[6];   # 
#
my $tempfilt="temp_sp_filt.fits";
my $temp1="temp_sp_temp1";
my $temp2="temp_sp_temp2";
#
# Create a list of X values with this Y range
#
# Set the attitude relative to the slew start position
my $c_evselect = "evselect table=\"$infile\" filtertype=expression ";
$c_evselect   .= "expression=\"(X in [$xstart:$xstop])&&(Y in [$ystart:$ystop])\" ";
$c_evselect   .= "writedss=yes destruct=yes filteredset=$tempfilt ";
$c_evselect   .= "withfilteredset=yes keepfilteroutput=yes "; 

runtask($c_evselect);

# Set the ranges needed depending on the split direction
my $rangeaxis = "X";
if ($dircn eq "X") 
     {$rangeaxis = "Y";}
#
# Create a sorted ascii list of the X or Y values
system("fdump \"$tempfilt+1\" prhead=no columns=\"$rangeaxis\" rows=\"-\" showcol=no showrow=no showunit=no clobber=yes $temp1" )  == 0 or 
           SAS::error("NoFtools","Couldn't run fdump on $tempfilt");

system("sed -e '/^\$/d' $temp1 | sort -n > $temp2") == 0 or
           SAS::error("SortFailed","Failed to sort $temp1");

# Get the list of X or Y ranges - maybe more than 1 
getranges($temp2,$outfile);
#
# Delete temporary files
system("rm $tempfilt $temp1 $temp2")  == 0 or
         SAS::error("NoClean","Failed to remove temporary files");
}

#
# getranges - gets the range of values which will go into each subimage
#
sub getranges{

my $infile  =$_[0];
my $outfile =$_[1];

open (XLIST, "<$infile") or die (" Can't open file $!\n");
my @xvals = <XLIST>;
my $nrange = 0;
my @xbeg;
my @xend;

# Set a minimum size for merging
my $minmerge = 50000.;
my $maxmerge = 72000.*2.0;

# Loop over each element and extract points where it changes by > 72000
#
$xbeg[0] = $xvals[0];
my $xlast = $xvals[0];

foreach my $x (@xvals) {

# check if there is a gap of 64800 between this event and the last one
   if ($x > ($xlast + 64800.)) {
#
      $xend[$nrange] = $xlast;

     # Merge the last two ranges if necessary
      if ( ($nrange > 0) && (($xend[$nrange] - $xbeg[$nrange]) < $minmerge)
              && (($xend[$nrange] - $xbeg[$nrange-1]) < $maxmerge)) {
         $xend[$nrange - 1] = $xend[$nrange];
         --$nrange;
         print "Combining range to: $xbeg[$nrange] $xend[$nrange]\n";
      }

     # Start the next range
      ++$nrange;
      $xbeg[$nrange] = $x;

   }

  # Else check if the event is >72000 from the start of this subimage
   elsif ($x > ($xbeg[$nrange]+72000.)) {

      ++$nrange;
      $xbeg[$nrange] = $xbeg[$nrange-1] + 64800;
      $xend[$nrange-1] = $xlast;
   }

   $xlast = $x;
}

# Close off the final range
$xend[$nrange] = $xlast;

# If the last range is small combine the last two ranges if doesn't become 
# too big
if ( ($nrange > 0) && (($xend[$nrange] - $xbeg[$nrange]) < $minmerge)
         && (($xend[$nrange] - $xbeg[$nrange-1]) < $maxmerge)) {
   $xend[$nrange - 1] = $xend[$nrange];
   --$nrange;
   print "Combining range to: $xbeg[$nrange] $xend[$nrange]\n";
}
   
#
# Output results
#
open (OLIST, ">$outfile") or die (" Can't open file $!\n");
#
for (my $xr = 0; $xr <= $nrange; $xr++) {
 printf OLIST "%d %d\n",$xbeg[$xr],$xend[$xr];
}

close (OLIST) or die (" Can't close file\n");
}
#
# Gets RA, DEC, revolution and obsid from the FITS file
#
sub findcelcent
{
my $infile=$_[0];
my $ra=0; my $dec=0; my $rev=0; my $obs=0;

$ra=getKeyWord($infile, 'REFXCRVL');
$dec=getKeyWord($infile, 'REFYCRVL');
$rev=getKeyWord($infile, 'REVOLUT');
$obs=getKeyWord($infile, 'OBS_ID');

# Get the RA in the right form
my $cra=sprintf("%3.4f",$ra);
if ($ra < 10.0)
  {$cra="00$cra";}
elsif ($ra < 100.0)
  {$cra="0$cra";}


# Get the DEC in the right form
my $cdec=0.0;
if ($dec >= 10.0 )
   {$cdec=sprintf("+%2.4f",$dec);}
elsif ($dec >= 0.0 )
   {$cdec=sprintf("+0%1.4f",abs($dec));}
elsif ($dec > -10.0 )
   {$cdec=sprintf("-0%1.4f",abs($dec));}
else
   {$cdec=sprintf("-%2.4f",abs($dec));}

# Set revolution to 4 digits
my $revolut=sprintf("%04d",$rev);

# remove quotes from OBSID
$obs =~ s/'//g;

my $ostring=sprintf("$cra $cdec $revolut $obs");
print "$ostring\n";

return $ostring;

}
#
# Usage: findTimeRange<eventfile>
# Purpose: find the max and min times present in an event file
#
sub findtimerange
{
   my $evfile=$_[0];
   my $tmpfile = 'del_fstat';

   system("fstatistic infile=$evfile colname='TIME' rows='-' outfile=$tmpfile clobber=yes") == 0 or SAS::error("NoFtools","Couldn't run fstatistic");

   my $min = getlastnum($tmpfile, "minimum");
   my $max = getlastnum($tmpfile, "maximum");

my $ostring=sprintf("$min $max");
print "$ostring\n";

 # Clean up
   system("rm $tmpfile ") ==0
         or SAS::error("NoClean","Failed to remove temporary file");

return $ostring;
}


#
# Usage: atthkchop <eventfile>
# Purpose: to subset an attitude file over the times present in
#          an event file +/- 75 seconds> NB +/- 30 secs as before gives
#          bad exposures at the beginning of the slew now.
#
sub atthkchop
{
my $evfile=$_[0];
#

   my $tmpfile = 'del_fstat';

   system("fstatistic infile=$evfile colname='TIME' rows='-' outfile=$tmpfile clobber=yes") == 0 or SAS::error("NoFtools","Couldn't run fstatistic");

   my $min = getlastnum($tmpfile, "minimum");
   my $max = getlastnum($tmpfile, "maximum");

$min = $min - 75.0;
$max = $max + 75.0;

my $command=sprintf("(TIME > $min && TIME < $max)");
#
# Subset the attitude file
#rm -f temp_sp_atthk_chopped.dat
   system("fselect infile=atthk.dat outfile=temp_sp_atthk_chopped.dat clobber=yes expr=\"$command\"") == 0 or
           SAS::error("NoFtools","Couldn't run fselect");

 # Clean up
   system("rm $tmpfile ") ==0
         or SAS::error("NoClean","Failed to remove temporary file");
}


# 
# rejig_attitude
#
# Derive the attitude from an event file.
#
# Finds the RA, DEC of a given X,Y position in an event file
#
sub rejig_attitude{

   my $filtfile=$_[0];
#
# Try deriving the attitude
   rejig_attitude_internal($filtfile);
#
# Check how well it worked
   my $refx=getKeyWord($filtfile, 'REFXCRPX');
   my $refxmin=getKeyWord($filtfile, 'REFXDMIN');
   my $refxmax=getKeyWord($filtfile, 'REFXDMAX');
   my $refy=getKeyWord($filtfile, 'REFYCRPX');
   my $refymin=getKeyWord($filtfile, 'REFYDMIN');
   my $refymax=getKeyWord($filtfile, 'REFYDMAX');

   print "Ref1 X: $refx $refxmin $refxmax\n";
   print "Ref1 Y: $refy $refymin $refymax\n";
 
# If either ref point is outside range - try again
   if ( $refx < $refxmin || $refx > $refxmax || $refy < $refymin 
                         || $refy > $refymax)
   {
     rejig_attitude_internal($filtfile);

     my $refx=getKeyWord($filtfile, 'REFXCRPX');
     my $refxmin=getKeyWord($filtfile, 'REFXDMIN');
     my $refxmax=getKeyWord($filtfile, 'REFXDMAX');
     my $refy=getKeyWord($filtfile, 'REFYCRPX');
     my $refymin=getKeyWord($filtfile, 'REFYDMIN');
     my $refymax=getKeyWord($filtfile, 'REFYDMAX');

     print "Ref2 X: $refx $refxmin $refxmax\n";
     print "Ref2 Y: $refy $refymin $refymax\n";
   }

}

#
# rejig_attitude_internal
#
# Finds the RA, DEC of a given X,Y position in an event file
#
sub rejig_attitude_internal{

my $filtfile=$_[0];
#
my $tempfits="temp_sp_tempfits";
#
my @celpos=findradec($filtfile, $tempfits);
my $newra=$celpos[0];
my $newdec=$celpos[1];
print "POSITIONS are: $newra $newdec\n";

# Reset the attitude

my $c_attcalc = "attcalc eventset=\"$filtfile\" imagesize=200.0 ";
$c_attcalc   .= "refpointlabel=user nominalra=\"$newra\" ";
$c_attcalc   .= "nominaldec=\"$newdec\" withatthkset=yes ";
runtask($c_attcalc);

@celpos=findradec($filtfile, $tempfits);
$newra=$celpos[0];
$newdec=$celpos[1];

print "Rederived position: $newra $newdec\n";

$c_attcalc = "attcalc eventset=\"$filtfile\" imagesize=200.0 ";
$c_attcalc   .= "refpointlabel=user nominalra=\"$newra\" ";
$c_attcalc   .= "nominaldec=\"$newdec\" withatthkset=yes ";
runtask($c_attcalc);

@celpos=findradec($filtfile, $tempfits);
$newra=$celpos[0];
$newdec=$celpos[1];

print "Rederived position 2: $newra $newdec\n";

$c_attcalc = "attcalc eventset=\"$filtfile\" imagesize=200.0 ";
$c_attcalc   .= "refpointlabel=user nominalra=\"$newra\" ";
$c_attcalc   .= "nominaldec=\"$newdec\" withatthkset=yes ";
runtask($c_attcalc);

# Now we will check whether the CRPIX values are within acceptable
# limits. If not then we are probably in the situation where the 
# initial pointing position of the slew is ~180 degs away from the
# current position AND we are near one of the poles
my $crpix1=getKeyWord($tempfits, 'CRPIX1');
my $crpix2=getKeyWord($tempfits, 'CRPIX2');
print "$crpix1 $crpix2\n";

my $newraout=$newra;
my $newdecout=$newdec;

# Shift RA by 180 degs and see if the CRPIX values get tighter

$newra=$newra+180.0;
if ($newra > 360.0) {$newra=$newra-360.0;}

print "Retry using position: $newra $newdec\n";
my $filtfile2="filt_temp.fits";
system("cp $filtfile $filtfile2") == 0 or
           SAS::error("CopyFail","Couldn't copy filtered file");

$c_attcalc = "attcalc eventset=\"$filtfile2\" imagesize=200.0 ";
$c_attcalc   .= "refpointlabel=user nominalra=\"$newra\" ";
$c_attcalc   .= "nominaldec=\"$newdec\" withatthkset=yes ";
runtask($c_attcalc);

@celpos=findradec($filtfile2, $tempfits);
$newra=$celpos[0];
$newdec=$celpos[1];

my $crpix1b=getKeyWord($tempfits, 'CRPIX1');
my $crpix2b=getKeyWord($tempfits, 'CRPIX2');
#print "$crpix1b $crpix2b\n";

# calculate the diff from centre for first and second attempts
my $d1=sqrt( $crpix1 * $crpix1 + $crpix2 * $crpix2 );
my $d2=sqrt( $crpix1b * $crpix1b + $crpix2b * $crpix2b );
                                                                                
if ( $d1 > $d2 )
{
  print "Retry - Rederived position: $newra $newdec\n";

  $c_attcalc = "attcalc eventset=\"$filtfile2\" imagesize=200.0 ";
  $c_attcalc   .= "refpointlabel=user nominalra=\"$newra\" ";
  $c_attcalc   .= "nominaldec=\"$newdec\" withatthkset=yes ";
  runtask($c_attcalc);

  @celpos=findradec($filtfile2, $tempfits);
  $newra=$celpos[0];
  $newdec=$celpos[1];

  print "Retry - Rederived position 2: $newra $newdec\n";

  $c_attcalc = "attcalc eventset=\"$filtfile2\" imagesize=200.0 ";
  $c_attcalc   .= "refpointlabel=user nominalra=\"$newra\" ";
  $c_attcalc   .= "nominaldec=\"$newdec\" withatthkset=yes ";
  runtask($c_attcalc);

  system("cp $filtfile2 $filtfile") == 0 or
           SAS::error("CopyFail","Couldn't copy filtered file");

  $newraout=$newra;
  $newdecout=$newdec;

} # End of if d1>d2 block

# Update the RA_PNT, DEC_PNT keywords as well to avoid problems with
# eboxdetect
system("fparkey value=$newraout fits=$filtfile+0 keyword=RA_PNT");
system("fparkey value=$newdecout fits=$filtfile+0 keyword=DEC_PNT");

# Clear up
system("rm $filtfile2 $tempfits");

} # End of rejig_attitude_internal

#
# findradec - Finds the RA, DEC of a given X,Y position in an event file
#
sub findradec{

#print "Entered findradec\n";
  my $filtfile=$_[0];
  my $outimage=$_[1];
#  my $outfile="temp_sp_rai_1";
#
#  First find mean value of X/Y positions in input file
#print "Entered findradec $filtfile\n";

  my $tmpfile = 'del_fstat';

  system("fstatistic infile=$filtfile  colname='X' rows='-' outfile=$tmpfile clobber=yes") == 0 or SAS::error("NoFtools","Couldn't run fstatistic");

  my $xcen = getlastnum($tmpfile, "mean");

  system("fstatistic infile=$filtfile  colname='Y' rows='-' outfile=$tmpfile clobber=yes") == 0 or SAS::error("NoFtools","Couldn't run fstatistic");

  my $ycen = getlastnum($tmpfile, "mean");

  my $xminbit=int($xcen-3200);
  my $xmaxbit=int($xcen+3200); 
  my $yminbit=int($ycen-3200);
  my $ymaxbit=int($ycen+3200);

  system("evselect table=$filtfile filtertype=expression expression=true writedss=yes xcolumn=X ycolumn=Y ximagebinsize=800 yimagebinsize=800 squarepixels=yes imageset=$outimage imagebinning=binSize withimageset=yes specchannelmin=0 specchannelmax=20479 ximagemin=$xminbit ximagemax=$xmaxbit withxranges=yes yimagemin=$yminbit yimagemax=$ymaxbit withyranges=yes raimagecenter=0 decimagecenter=0 withcelestialcenter=no timemin=0 timemax=1000 withtimeranges=no maketimecolumn=no makeratecolumn=no withrateset=no histogrammin=0 histogrammax=1000 withhistoranges=no") ==0 or SAS::error("NoEVFILE","evselect failed in findradec");

  my $tempfile="temp_sp_ereg";
  system("ecoordconv imageset=$outimage withcoords=yes x=$xcen y=$ycen pos2eqpos=yes | grep \"RA: DEC:\" > $tempfile") ==0 or SAS::error("EcoordFail","ecoordconv failed"); # If fails send to tempfile 

 # Extract the RA, DEC from the input region centre line
  my @celpos;
  open (OUTFILE, "<$tempfile") or die (" Can't open file $!\n");
  while (my $outline = <OUTFILE>) {
     chomp $outline;
     #print "OUTLINE: $outline\n";
     (my @list) = split " ", $outline;
     $celpos[0]=$list[2];
     $celpos[1]=$list[3];
  }

 # Clean up
  system("rm $tempfile $tmpfile ") ==0
         or SAS::error("NoClean","Failed to remove temporary file");

  print "CELPOS: $celpos[0] $celpos[1]\n";

  return @celpos;
}

#
#==============================================================================
# getVersion : get the version number of eslewchain
#

sub getVersion {
   my $eslewchain_msg = -$SAS::AppMsg;
   my $ccom = "" ; my $version = "" ; my $release = "";
   my $vfile = $ENV{'SAS_DIR'} . "/packages/eslewchain/VERSION" ;
   if ( ! -e $vfile ) {
     SAS::message($SAS::AppMsg, $SAS::SparseMsg, "Not found: $vfile");
     SAS::message($SAS::AppMsg, $SAS::SparseMsg, "Take version from task.");
     $version = $TASK_VERSION }
   else {
     $ccom = "cat `saslocate packages/eslewchain/VERSION` /dev/null" ;
     chomp($version = `$ccom`) ;
   };
   $vfile = $ENV{'SAS_DIR'} . "/RELEASE" ;
   if ( ! -e $vfile ) {
     $release = "" }
   else {
     $ccom = "cat `saslocate RELEASE`" ;
     chomp($release = `$ccom`) ;
   };
   SAS::message($SAS::AppMsg, $eslewchain_msg, "");
   SAS::message($SAS::AppMsg, $eslewchain_msg, "eslewchain (eslewchain-$version) [$release]");
}

#
#==============================================================================
# in case of early error show the full syntax, 
#   also for options "--p" and "-p" and "--h" and "-h"
#
#sub showSyntax {
#  my $indir = "";
#  if ( not exists $ENV{'SAS_ODF'}) {}
#  else { $indir = $ENV{'SAS_ODF'} }

#  my $eslewchain_msg = -$SAS::AppMsg;
#  SAS::message($SAS::AppMsg, $eslewchain_msg, "");
#  SAS::message($SAS::AppMsg, $eslewchain_msg, "Syntax: eslewchain odf=<ODF directory>    [$indir]");
#}

#
#==============================================================================
# addSlewKeys: write slew specific keywords into the image and exposure 
#              map headers
#
sub addSlewKeys {

  # Input @_ = Names of files to use
    my $tstart = $_[-2];
    my $tstop = $_[-1];

    print "Times:  $tstart $tstop $_[-3]\n";

    my $exp = ($tstop - $tstart) * 86400.0;
 
  # Find the image stem from the first filename
    my $image_stem = (substr $_[0], 0, 11)  . "_" . (substr $_[0], 24, 3) ;

  # Write a temporary file to contain the keywords to write
    my $modhead_tempfile = "temp_header_keywords";

    open (HEADFILE, ">$modhead_tempfile");
    print HEADFILE "OBJECT  $image_stem  / Stem of image name\n";
    print HEADFILE "OBSERVER  XMM-Newton / Name of PI\n";
    print HEADFILE "MJDSTART $tstart / The start time for this subimage (MJD)\n";
    print HEADFILE "MJDSTOP $tstop / The end time for this subimage (MJD)\n";
    print HEADFILE "EXPOSURE $exp / The exposure time of this subimage (sec)\n";
    close (HEADFILE);

  # Loop over each FITS file and add keywords to the primary header
    my @files = splice @_, 0, -2;
    print "Files: @files\n";

     foreach (@files) {
        system("fmodhead infile='$_+0' tmpfil=$modhead_tempfile") == 0 or 
                           SAS::error("NoFtools","Couldn't run fstatistic");
     }

  # Remove the temporary file
     system("rm $modhead_tempfile") ==0
         or SAS::error("NoClean","Failed to remove temporary file");
}

#
##==============================================================================
## make_png_files: make png files for each image
#
sub make_png_files {

  # Input @_ = Names of files to use
  my @files = splice @_, 0;

  foreach (@files) {
     system("implot colourmap=1 withzclip=no set='$_' device=/png") == 0 or
                           SAS::error("ImplotFailed","Couldn't run implot");

     my $outfile = (substr $_, 0, 27) . ".png";

     print "Produced: $outfile\n";

     system("mv pgplot.png $outfile") ==0
         or SAS::error("NoMove","Failed to rename png file");     
  }
}

#
#==============================================================================
# RenameAndClean: change the name of some output files and delete some
#                 temporary files
#
sub RenameAndClean {

   # Rename input parameters
    my $obs = $_[0];
    my $evfile = $_[1];
    
   # Attitude file
    my $attfile =  "P" . $obs . "OBX000ATTTSR0000.ds";
    system("mv atthk.dat $attfile") ==0
         or SAS::error("NoRename","Failed to rename attitude file");

   # Total slew event file
    #my $outevfile = "P" . $obs . "PNS" . "003" . "PIEVLI0SLW.ds";
    my $outevfile = "P" . $obs . "PNS" . "003" . "SLEVLI0000.ds";

    system("cp $evfile $outevfile") ==0
         or SAS::error("NoRename","Failed to copy FULL event file");

   # Per slew step image and exposure maps and event files are already ok

   # Remove temp files
     system("rm histo.fits image.fits spectrum.fits fdelout.del") ==0
         or SAS::error("NoClean","Failed to remove temporary file");

}

#
#==============================================================================
# checkExpExtns : checks if all exposure extensions are present in the evt file
#
sub checkExpExtns {

   # Rename input parameters
    my $evfile = $_[0];
   
   # Get a list of the blocks in this file
  my $tempfile="temp_blocks";
  system("fstruct infile=$evfile | grep \"BINTABLE\" | grep \"EXPOS\" > $tempfile") ==0 or SAS::error("BlockCountFail","fstruct failed"); # If fails send to tempfile 

   # Count the number of exposure blocks
  my $blkcnt=0;
  open (INFILE, "<$tempfile") or die (" Can't open file $!\n");
  while (my $blockname = <INFILE>) 
          { $blkcnt++; }

 # Clean up
  system("rm $tempfile ") ==0 or 
            SAS::error("NoClean","Failed to remove temporary file"); 

 # Exit if not exactly 12 exposure extensions
 print "Exposure block count: $blkcnt\n"; 
  if ($blkcnt != 12) 
    { SAS::error("MissingExpExtns","The event file is missing one or more exposure extensions - exiting")};

}

 #
 #
#
#==============================================================================
# Delete_exposure_xtns: remove exposure extensions from an event file
#
sub delete_exposure_xtns {

   # Rename input parameters
    my $filtfile = $_[0];

   # Remove the exposure extensions from this file - should be 12
   # This may legitimately fail - supress error messages
    my $fdeloutput = "fdelout.del";
    system("fdelhdu $filtfile\[EXPOSU01] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU02] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU03] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU04] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU05] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU06] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU07] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU08] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU09] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU10] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU11] NO YES > $fdeloutput 2>&1");
    system("fdelhdu $filtfile\[EXPOSU12] NO YES > $fdeloutput 2>&1");

} # End of delete_exposure_xtns

#
#==============================================================================
# A routine to crudely convert from MRT to MJD (no leap secs)
#
sub MRTtoMJD {

    my $mrt = $_[0];

   # Define the MJD where MRT is zero (actually 1997-12-31T23:58:56.816 UTC)
    my $mjd0 = 50813.9992687037;

   # Calculate MJD for this input MRT
    my $mjd = $mjd0 + $mrt / 86400.0;

    $mjd = addLeapSeconds($mjd);

    return $mjd;

} # End of mrt to mjd conversion

#
#==============================================================================
# A routine to crudely convert from MRT to MJD (no leap secs)
#
sub addLeapSeconds {

    my $mjd = $_[0];

   # Add on defined leap seconds
    if ($mjd > 51179.0) {$mjd = $mjd + 1.0 / 86400.0};
    if ($mjd > 53736.0) {$mjd = $mjd + 1.0 / 86400.0};
    if ($mjd > 54832.0) {$mjd = $mjd + 1.0 / 86400.0};
    if ($mjd > 56109.0) {$mjd = $mjd + 1.0 / 86400.0};
 
    return $mjd;

} # End off addLeapSeconds

#
#==============================================================================
# A routine to get the MakePng command line parameter {
#
sub getMakePngParam {

    my $makepng=0;

    print "PARAMS: @ARGV\n";

    if ( grep /^withpng=yes/ , @ARGV) {$makepng=1;};

    return $makepng;
}

exit
