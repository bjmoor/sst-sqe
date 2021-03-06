#!/bin/bash 
# testSuite_memHierarchy.sh

# Description: 

# A shell script that defines a shunit2 test suite. This will be
# invoked by the Bamboo script.

# Preconditions:

# 1) The SUT (software under test) must have built successfully.
# 2) A test success reference file is available.

TEST_SUITE_ROOT="$( cd -P "$( dirname "$0" )" && pwd )"
# Load test definitions
. $TEST_SUITE_ROOT/../include/testDefinitions.sh
. $TEST_SUITE_ROOT/../include/testSubroutines.sh

## set TIMELIMT for each test in Suite
export SST_TEST_ONE_TEST_TIMEOUT=100         #  100 seconds
FAIL_LIST=" "
DRAMSIM_EXACT_MATCH_FAIL_COUNT=0

#===============================================================================
# Variables global to functions in this suite
#===============================================================================
L_SUITENAME="SST_memHierarchy_sdl_suite" # Name of this test suite; will be used to
                                 # identify this suite in XML file. This
                                 # should be a single string, no spaces
                                 # please.

L_BUILDTYPE=$1 # Build type, passed in from bamboo.sh as a convenience
               # value. If you run this script from the command line,
               # you will need to supply this value in the same way
               # that bamboo.sh defines it if you wish to use it.

L_TESTFILE=()  # Empty list, used to hold test file names

#===============================================================================
#                       TEMPLATE
#     Subroutine to run many of the memHierarchy tests without reproducing the script.
#      First parameter is the name of the test, must match test_memHierarchy_<name>()
#      Second parameter is the execution cycle tolerance in hundredths of a
#         percent.   (5% therefore is 500.)
export EXACT=0
export COUNT_SST_FAILS=0
rm -f ${SST_TEST_INPUTS_TEMP}/$$_diffSummary

memHierarchy_Template() {
memH_case=$1
Tol=$2    ##  curTick tolerance

    startSeconds=`date +%s`
    testDataFileBase="test_memHierarchy_$memH_case"
    outFile="${SST_TEST_OUTPUTS}/${testDataFileBase}.out"
    tmpFile="${SST_TEST_OUTPUTS}/${testDataFileBase}.tmp"
    errFile="${SST_TEST_OUTPUTS}/${testDataFileBase}.err"
    referenceFile="${SST_TEST_REFERENCE}/${testDataFileBase}.out"
    # Add basename to list for processing later
    L_TESTFILE+=(${testDataFileBase})
    memH_sdl_dir=$SST_ROOT/sst/elements/memHierarchy/tests
    rm -f $memH_sdl_dir/dramsim*log
    pushd $SST_ROOT/sst/elements/memHierarchy/tests

    sut="${SST_TEST_INSTALL_BIN}/sst"

    pyFileName=`echo ${memH_case}.py | sed s/_/-/`
    sutArgs=$memH_sdl_dir/$pyFileName
    echo $sutArgs
    grep backend $sutArgs | grep dramsim > /dev/null
    usingDramSim=$?

    ls $sutArgs > /dev/null
    if [ $? != 0 ]
    then
      ls $sutArgs
      echo ' FAILED to find Python file.'
      echo ' '
      ls ${memH_sdl_dir}/*.py
      echo ' '
      fail ' FAILED to find Python file.'
      popd
      return
    fi

    ${sut} ${sutArgs} > ${tmpFile}  2>${errFile}
    if [ $? != 0 ]
    then
         echo ' '; echo WARNING: sst did not finish normally ; echo ' '
         ls -l ${sut}
         fail "WARNING: sst did not finish normally"
         if [ -s ${errFile} ] ; then
             notAlignedCt=`grep -c 'not aligned to the request size' $errFile`
             echo ' ' ; echo "* * * *  $notAlignedCt Not Aligned messages from $memH_case   * * * *" ; echo ' '
             echo "         stderr File  $memH_case"
             cat $errFile | grep -v 'not aligned to the request size'
             echo "          ----------"
         fi
         popd
         return
    fi
#                   --- It completed normally ---
    notAlignedCt=`grep -c 'not aligned to the request size' $errFile`
    if [ $notAlignedCt != 0 ] ; then
        echo ' ' 
        if [ $usingDramSim == 0 ] ; then    ## usingDramSim is TRUE
             echo "          This case uses DramSim"
        fi
        echo "* * * *   $notAlignedCt Not Aligned messages from $memH_case   * * * *" ; echo ' '
    fi

    if [ -s ${errFile} ] ; then
        echo "         STDERR (omiting \"not aligned\" messages)"
        cat $errFile | grep -v 'not aligned to the request size'
        echo "         ----- end stderr"
    fi

    grep -v ^cpu.*: $tmpFile > $outFile
    diff $referenceFile $outFile > /dev/null    # SHOULD THIS BE SAVED?
    if [ $? == 0 ] ; then
        fileSize=`wc -l $outFile | awk '{print $1}'`
        echo "            Exact Match of reduced Output  -- $fileSize lines"
    else
        echo "`diff $referenceFile $outFile | wc` $memH_case" >> ${SST_TEST_INPUTS_TEMP}/$$_diffSummary
#                             --- Special case with-DramSim --- 
        if [ $usingDramSim == 0 ] ; then    ## usingDramSim is TRUE
           echo "            wc the diff"
           diff ${outFile} ${referenceFile} | wc; echo ' '
           ref=`wc ${referenceFile} | awk '{print $1, $2}'`; 
           new=`wc ${outFile}       | awk '{print $1, $2}'`;
           if [ "$ref" == "$new" ];
           then
               echo " Word / Line count of matches (using DRAMSim)"

               FAIL_LIST="$FAIL_LIST $memH_case"

               DRAMSIM_EXACT_MATCH_FAIL_COUNT=$(($DRAMSIM_EXACT_MATCH_FAIL_COUNT+1 ))
#              echo " COUNT $DRAMSIM_EXACT_MATCH_FAIL_COUNT"
#              echo " [${FAIL_LIST}]"

           else 
               echo " FAILURE:    Line / Word count do not agree "
               FAIL_LIST="$FAIL_LIST $memH_case"
               DRAMSIM_EXACT_MATCH_FAIL_COUNT=$(($DRAMSIM_EXACT_MATCH_FAIL_COUNT+1 ))
               if [ -s $errFile ]; then
                   echo  "STDERR is:    ------------------"
                   cat $errFile | grep -v 'not aligned to the request size'
                   echo  "END of STDERR --------------------"
               fi
               fail " FAILURE:    Line / Word count do not agree (using DRAMSIM)"
           fi          
                        ##    --- end of code for Dramsim case ----
        else
                        ##    --- Do a sorted compare ---
           compare_sorted ${referenceFile} ${outFile}
           if [ $? == 0 ] ; then
               echo " # Sorted outFile and Reference match exactly # "
           else
               echo ' ' ; echo " # Sorted files Output and Reference do not match #"
               echo " Not failing !    Should we? " ; echo ' '
               sed 15q diff_sorted
           fi
        fi
    fi
    echo "     `grep "Simulation is complete, simulated time:" $tmpFile`"
    if [ $? != 0 ] ; then 
        echo "Completion test message not found"
        fail "Completion test message not found"
        echo ' '; grep -i complet $tmpFile ; echo ' '
    else
        echo "Ref: `grep "Simulation is complete, simulated time:" $referenceFile`"
    fi
  
    endSeconds=`date +%s`
    elapsedSeconds=$(($endSeconds -$startSeconds))
    echo "${memH_case}: Wall Clock Time  $elapsedSeconds seconds"
    echo " "
    popd

}


# Build Test app
  

#===============================================================================
# Test functions
#   NOTE: These functions are invoked automatically by shunit2 as long
#   as the function name begins with "test...".
#===============================================================================

#-------------------------------------------------------------------------------
# Test:
#     test_memHierarchy
# Purpose:
#     Exercise the memHierarchy code in SST
# Inputs:
#     None
# Outputs:
#     test_memHierarchy_Hw.out file
# Expected Results
#     Match of output file against reference file
# Caveats:
#     For shunit2, the output files must match the reference file *exactly*,
#     requiring that the command lines for creating both the output
#     file and the reference file be exactly the same.
# Exception for memHierarchy tests:
#     A fuzzy compare has been inserted here.   The only thing that varies is
#     the value of the total Ticks simulated.  With binaries shared from SVN, 
#     there should be no need for fuzziness.  When the static binary is built
#     using compiler and libraries on the host, the exact number of Ticks in the 
#     program may vary from that reported in the reference file checked into SVN.
# Does not use subroutine because it invokes the build of all test binaries.
#-------------------------------------------------------------------------------
#
#  sdl-1   Simple CPU + 1 level cache + Memory
#
test_memHierarchy_sdl_1() {          
echo Begin first memH test
memHierarchy_Template sdl_1 500

}

#
#  sdl-2  Simple CPU + 1 level cache + DRAMSim Memory
#
test_memHierarchy_sdl_2() {          
memHierarchy_Template sdl_2 500
}

#
#  sdl-3  Simple CPU + 1 level cache + DRAMSim Memory (alternate block size)
#
test_memHierarchy_sdl_3() {          
memHierarchy_Template sdl_3 500
}

#
#  sdl2-1  Simple CPU + 2 levels cache + Memory
#
test_memHierarchy_sdl2_1() {          
memHierarchy_Template sdl2_1 500
}

#
#  sdl3-1  2 Simple CPUs + 2 levels cache + Memory
#
test_memHierarchy_sdl3_1() {          
memHierarchy_Template sdl3_1 500
}

#
#  sdl3-2  2 Simple CPUs + 2 levels cache + DRAMSim Memory
#
test_memHierarchy_sdl3_2() {          
memHierarchy_Template sdl3_2 500

}

#
#  sdl3-3  
#
test_memHierarchy_sdl3_3() {          
memHierarchy_Template sdl3_3 500

}

test_memHierarchy_sdl4_1() {          
memHierarchy_Template sdl4_1 500
}

test_memHierarchy_sdl4_2() {          
memHierarchy_Template sdl4_2 500

}

test_memHierarchy_sdl5_1() {          
memHierarchy_Template sdl5_1 500
}

test_memHierarchy_sdl8_1() {          
memHierarchy_Template sdl8_1 500

}

test_memHierarchy_sdl8_3() {          
memHierarchy_Template sdl8_3 500

}

test_memHierarchy_sdl8_4() {          
memHierarchy_Template sdl8_4 500

}

test_memHierarchy_sdl9_1() {
memHierarchy_Template sdl9_1 500
}

test_memHierarchy_sdl9_2() {          
memHierarchy_Template sdl9_2 500

}

test_print_DramSim_summary() {

    if [ $DRAMSIM_EXACT_MATCH_FAIL_COUNT != 0 ] ; then
        echo "DramSim exact match failed on:" > $$_tmp
        echo $FAIL_LIST  >> $$_tmp
    else
        echo "        DramSim sdl tests all got exact match"  >> $$_tmp
    fi
    echo ' '
    skip_this_test
}


export SHUNIT_DISABLE_DIFFTOXML=1
export SHUNIT_OUTPUTDIR=$SST_TEST_RESULTS


# Invoke shunit2. Any function in this file whose name starts with
# "test"  will be automatically executed.
(. ${SHUNIT2_SRC}/shunit2)

