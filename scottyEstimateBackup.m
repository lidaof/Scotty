function [ h ] = scottyEstimate( fileName, nControlSamples, nTestSamples, outputTag, ...
    fc, pCut, minPercDetected, costPerRepControl, costPerRepTest, costPerMillionReads, totalBudget, ...
    maxReps, minReadsPerRep, maxReadsPerRep, minPercUnBiasedGenes, pwrBiasCutoff)
    %This is the main file for the Scotty application.
    %It is called as and exectuable by the Scotty.php web page.
    %This file and associated ones are located in C:\Work\Scotty\
    %The package can be built using the build gui on this computer
    %For the server we have to use mcc

    %==============================================
    %Preliminaries
    %==============================================
    warning('off', 'MATLAB:DELETE:FileNotFound');
    warningString='<h3>Warnings</h3>';
    
 
    %Set up graphics output configuration   
    
    set(gcf,'PaperUnits','inches','PaperPosition',[0 0 4.3 3]) 
    %set(gcf,'Renderer','painters')
   
    
    statusesConversion=0;
    cutOff=10;
    
    tic
  
    %==============================================
    %Read inputs from the command line
    %==============================================

    if isdeployed()==0     
        fileName='C:\Scotty\ComparisonResults\SampleData2FC10Reps_trial_3.txt';
        fileName='C:\Scotty\data\HumanBCellKasowskiUniquLines.txt';
        %fileName='C:\Scotty\data\HumanBCellCheung.txt';        
        nControlSamples=10;
        nTestSamples=0;
        outputTag='040503';
        pCut=0.01;
        minPercDetected=50;
        nReplicates=2;
        overdispersion=0;
        outputDirectory='C:\scotty\data\';
        cutOff=10;%Sequencing depth (p)
        costPerRepControl=100;
        costPerRepTest=100;
        costPerMillionReads=10;
        totalBudget=12000;
        optimizationType=3;
        fc=2;
        nReadsPerSample=1000000;
        maxReps=10;
        minReadsPerRep=10^7;
        maxReadsPerRep=10^8;
        minPercUnBiasedGenes=40;
        statusesConversion=ones(14,1);
        pwrBiasCutoff=50;
    elseif isdeployed()==1  
        %Sends all as a string so have to switch the double
        [nControlSamples statusesConversion(1)]=str2num(nControlSamples);
        [nTestSamples statusesConversion(2)]=str2num(nTestSamples);
        [fc statusesConversion(3)]=str2num(fc);
        [pCut statusesConversion(4)]=str2num(pCut);
        [minPercDetected statusesConversion(5)]=str2num(minPercDetected);
        [costPerRepControl statusesConversion(6)]=str2num((regexprep(costPerRepControl,',','')));
        [costPerRepTest statusesConversion(7)]=str2num((regexprep(costPerRepTest,',',''))); 
        [costPerMillionReads statusesConversion(8)]=str2num((regexprep(costPerMillionReads,',','')));   
        [totalBudget statusesConversion(9)]=str2num((regexprep(totalBudget,',',''))); 
        [maxReps statusesConversion(10)]=str2num(maxReps);           
        [minReadsPerRep statusesConversion(11)]=str2num((regexprep(minReadsPerRep,',',''))); 
        [maxReadsPerRep statusesConversion(12)]=str2num((regexprep(maxReadsPerRep,',','')));   
        [minPercUnBiasedGenes statusesConversion(13)]=str2num(minPercUnBiasedGenes);
        [pwrBiasCutoff statusesConversion(14)]=str2num(pwrBiasCutoff);
        outputDirectory='/var/www/html/marthlab/scotty/outputFiles/'; %TO DO: This should really be set in the PHP
    end
    
    pwrBiasCutoff=pwrBiasCutoff/100;
    %Check inputs for errors
    if sum(statusesConversion)~=14
        statusConversion
        error('Matlab Error: A non-numeric value was found in one of the entries.  Please check your inputs.');
    end
    
    %set up file for results, write to this if there are warnings
    filename=strcat(outputDirectory,'resultsSummaryFile',outputTag,'.txt');
    delete(filename); 
    
    if isnan(pCut) || pCut<=0 || pCut>1        
        warningString=strcat(warningString, '<br>The p-value cut was not entered in the proper format. Set to 0.01.');
    end
    
    if nControlSamples<2 && nTestSamples==1
        warningString=strcat(warningString, '<br>No replicates were entered.  Using mean overdispersion of 0.3.');
    elseif nControlSamples<2 && nTestSamples==1
        warningString=strcat(warningString, '<br>No replicates were entered for the test condtion.  Assuming test variance is the same as control.');
    elseif nControlSamples<2 && nTestSamples>1
        warningString=strcat(warningString, '<br>No replicates were entered for the control condtion.  Assuming test variance is the same as test.');
    elseif nControlSamples+nTestSamples<1
         warningString=strcat(warningString, '<br>Replicates were entered for either condition.  Please fix the replicate counts. <a href="http://euler.bc.edu/marthlab/scotty/helpForms/formatInfo.html" target="_blank">See format info.</a></p>');
         error('Error: Control columns entered as zero.');
    end     
    
    nTotalSamples=nControlSamples+nTestSamples;
    
    %============================================================
    %Read Input Data
    %============================================================
    
    out='Reading file'
    
    try
    %Read the data file
        [ statusReport errorMessage geneNames data sampleNames ] = scottyReadDataFile( fileName, nControlSamples, nTestSamples  );           
    catch
         warningString=strcat(warningString, {'<br>Scotty was unable to parse the data file.  '} ...
             ,'Please ensure that the data is formatted <a href="http://euler.bc.edu/marthlab/scotty/help.html#PilotFormat" target="_blank"> as specified </a></p>' ...
             ,'and the the control and test column counts are correct.');
         printResultFile( warningString{1}, outputDirectory, outputTag );
         error('Error: Could not read data file.');
    end
    
    if statusReport == 1
        warningString=strcat(warningString, {'<br>Scotty was unable to parse the data file.  '} ...
             ,'Please ensure that the data is formatted <a href="http://euler.bc.edu/marthlab/scotty/help.html#PilotFormat" target="_blank"> as specified </a></p>' ...
             ,'and the the control and test column counts are correct.');
         printResultFile( warningString{1}, outputDirectory, outputTag );
         error('Error: Could not read data file.');
    end
    
    out='replacing bad data'
        
    if sum(sum(isnan(data)))>0
         [r c]=find(isnan(data));         
         warningString=strcat(warningString, {'<br>Scotty was unable to parse the data file on '}, num2str(length(r)), {' lines including line '}, ...
             num2str(r(1)),'. Please ensure that the data is formatted <a href="http://euler.bc.edu/marthlab/scotty/help.html#PilotFormat" target="_blank"> as specified </a></p>', ...
             'and that the control and test column counts are correct.');
         printResultFile( warningString{1}, outputDirectory, outputTag )
         error('Error: NaN data files.');
    end
    
    totalReadCounts=sum(data,1);
    totalReadsControl=totalReadCounts(1:nControlSamples);
    totalReadsTest=totalReadCounts(nControlSamples+1:nControlSamples+nTestSamples);        
    
   
   
    %============================================================
    %Set up the matlab processor pool.  This takes a while
    %so I put it after the file reading, so it will crash
    %faster if there is a problem with the files or input
    %====================

    out='starting matlab pool'
    try
        matlabpool
    catch
        warningString=strcat(warningString, '<br>Matlab pooling is not available. This will not affect findings but processing time will be slowed.  Please contact us if this problem persists.');
    end
   
    
    %Do the data quality steps first in case there is a problem with
    %the data that causes Matlab to crash.  The quality plots should
    %still be visible.
    
    %============================================================
    %If there are 3 or more samples, cluster the samples 
    %as an initial quality step.  
    %============================================================
   
    out='clustering chart'
    
    if nTotalSamples>=3
        try
            [ clusteringChart ] = clusterSamples( data, sampleNames );        
            clusterFileName=strcat(outputDirectory,'cluster',outputTag,'.png');
            delete(clusterFileName);
            print(clusteringChart, '-dpng' , clusterFileName , '-r130')
        catch
            warningString=strcat(warningString, '<br>Clustering will not run.  This is sometimes occurs if datasets have too many similar points.  Please contact us for more information.');
        end
    end 
  
    
    
    
    try
        %============================================================
        %Analyze the sequencing depth
        %============================================================
        %Get the parameters of the  
        %To improve the quality of the estimate, all control samples
        %is aggregated into a single dataset, as are test.  This introduces 
        %some biological noise, but it is better to have a larger sample to make this
        %calculation on. Fitting the Poisson Lognormal distirbution has some
        %error when the variance is high compared to the mean.  Since the fit
        %is only used to estimate the number of unseen genes, adding the
        %samples together reduces Scotty's reliance on the quality of the fit 
        %of the lognormal poisson. 

       
        
        if nControlSamples>0
            out='getting sequence depth parameters control'
            controlDataAgg=sum(data(:, 1:nControlSamples),2);   
            [observedGenesC totalGenesExpressedC mFinalC vFinalC readsFinalC lognFitPlot probSequencedC] = getSequenceDepthParameters( controlDataAgg, sum(controlDataAgg), 'Control Data'); 
            filename1=strcat(outputDirectory,'lognFitControlPlot',outputTag,'.png');
            delete(filename1);    
            print(lognFitPlot, '-dpng' , filename1 , '-r130');    
        end

    
        if nTestSamples>0
            out='getting sequence depth parameters test'
                
            testDataAgg=sum(data(:, nControlSamples+1:nControlSamples+nTestSamples),2);    
            [observedGenesT totalGenesExpressedT mFinalT vFinalT readsFinalT lognFitPlot probSequencedT] = getSequenceDepthParameters(testDataAgg, sum(testDataAgg),'Test Data' );
            filename1=strcat(outputDirectory,'lognFitTestPlot',outputTag,'.png');
            delete(filename1);    
            print(lognFitPlot, '-dpng' , filename1 , '-r130');    
        end

        if nControlSamples==0 & nTestSamples>0
            probSequencedC=probSequencedT;
        end

        out='Sequence depth parmas variance got'
     

        %============================================================
        %Analyze the Variance
        %============================================================

        %This needs to be speeded up
        [ mVControl vVControl pVControl  mVTest vVTest pVTest  ] = getParamsVariance(data, nControlSamples, nTestSamples );   

        out='Parmas variance got'

        %============================================================
        %Generate Rarefaction Plots
        %============================================================

        %Start with empty matrices.  Fill them in later....
        genesFound=[];
        sampleIds=[];
        finalReadDepthMeans=[];
        finalReadDepthVars=[];
        readsSequenced=[];

        %This runs the probabilities separately for each dataset, to show if
        %there are any differences in saturation rates
        %Runs it to a target of 5x of what was actually sequenced
        meanTotal=mean(totalReadCounts,2);
        maxTotal=max(totalReadCounts);
        %Don't go over 10^9 takes too long
        targetFinalReadCount=min(maxTotal*5, 10^9);

        parfor i=1:size(data,2)
            [ readsRequired1 observedGenes1 totalGenesExpressed1 readsSequenced1 genesFound1 finalMeanSample finalVarSample] = getProbSequencedMonteCarloByReads( data(:,i), totalReadCounts(:,i), cutOff , targetFinalReadCount);
            readsRequired(i)=readsRequired1;
            totalGenesExpressed(i)=totalGenesExpressed1;
            readsSequenced=[readsSequenced; readsSequenced1;];
            genesFound=[genesFound; genesFound1;];
            sampleIds=[sampleIds; zeros(length(readsSequenced1),1)+i];
            finalReadDepthMeans(i)=finalMeanSample;
            finalReadDepthVars(i)=finalVarSample;     
        end
        [ rarefactionPlot ] = getRarefactionPlot( readsSequenced, genesFound, sampleIds, sampleNames, nControlSamples, nTestSamples, cutOff );
        filename1=strcat(outputDirectory,'rarefactionPlot',outputTag,'.png');
        delete(filename1);    
        print(rarefactionPlot, '-dpng' , filename1 , '-r130');    

         out='rarefaction plot got'

        mReadDepthControl=mean(finalReadDepthMeans(1:nControlSamples));    
        vReadDepthControl=mean(finalReadDepthVars(1:nControlSamples));


        %mVControl=0; vVControl=0; pVControl=0;  mVTest=0; vVTest=0; pVTest=0;
        %============================================================
        %Optimize Expweriment
        %============================================================
        insuffFunds=0;

        %============================================================
        %Get optimization plots
        %============================================================

        close all

        [powerPlot excludedPlot biasPlot costPlot allowedPlot cheapestExperiment mostPowerfulExperiment experimentsEvaluated pwrsCalc]=getOptimizationCharts(...
            maxReps, probSequencedC, mVControl, vVControl,  mVTest, vVTest, fc, pCut, costPerRepControl, costPerRepTest, costPerMillionReads, totalBudget, ...
            minReadsPerRep, maxReadsPerRep, minPercUnBiasedGenes, minPercDetected, pwrBiasCutoff,  nControlSamples+nTestSamples );    

         out='optimization done'

        filename1=strcat(outputDirectory,'powerPlot',outputTag,'.png');
        delete(filename1);
        print(powerPlot, '-dpng' , filename1 , '-r130');

        filename1=strcat(outputDirectory,'excludedPlot',outputTag,'.png');
        delete(filename1);
        print(excludedPlot, '-dpng' , filename1 , '-r130');

        filename1=strcat(outputDirectory,'allowedPlot',outputTag,'.png');
        delete(filename1);
        print(allowedPlot, '-dpng' , filename1 , '-r130');


        filename1=strcat(outputDirectory,'biasPlot',outputTag,'.png');
        delete(filename1);
        print(biasPlot, '-dpng' , filename1 , '-r130');


        filename1=strcat(outputDirectory,'costPlot',outputTag,'.png');
        delete(filename1);
        print(costPlot, '-dpng' , filename1 , '-r130');



        %============================================================
        %Get power plots
        %============================================================

        %Make plots for fold changes of 1.5, 2 and 3X
        fcsPlot=[1.5 2 3];      

        %Cheapest Allowed Experiment
        if isempty(cheapestExperiment)==0 %Only generates charts if one of them is good, to avoid confusion       

            bestNRepsRun=cheapestExperiment(2);
            bestReadDepthRun=cheapestExperiment(1); 

            meanProp=mFinalC/readsFinalC;
            stdProp=sqrt(vFinalC)/readsFinalC;
            mReadDepthControlBest=bestReadDepthRun*meanProp;
            vReadDepthControlBest=(bestReadDepthRun*stdProp)^2;


           %Makes a 3d matrix to send to the power plotter
            plotPowers=[];
            plotReadDepths=[];
            for i=1:3
                fcForPlot=fcsPlot(i); 
                readDepthsSampled=getReadDepthsRun(probSequencedC, bestReadDepthRun, 50, nControlSamples+nTestSamples); %gets 50 sequencing depths at evenly spaced increments
                plotReadDepths(:,i)=readDepthsSampled;
                plotPowers(:,:,i)=getPowerByReadDepth( mVControl, vVControl, mVTest, vVTest, readDepthsSampled, bestNRepsRun, bestNRepsRun,  fcForPlot, pCut, 1);
            end

            [ powerPlot ] = getPowerPlot(plotPowers, probSequencedC.*bestReadDepthRun, plotReadDepths, fcsPlot, pCut, bestNRepsRun, bestReadDepthRun );

            filename1=strcat(outputDirectory,'powerPlotCheapest',outputTag,'.png');
            delete(filename1);
            print(powerPlot, '-dpng' , filename1 , '-r130');


            %Most Powerful Experiment
            bestNRepsRun=mostPowerfulExperiment(2);
            bestReadDepthRun=mostPowerfulExperiment(1); 

            meanProp=mFinalC/readsFinalC;
            stdProp=sqrt(vFinalC)/readsFinalC;
            mReadDepthControlBest=bestReadDepthRun*meanProp;
            vReadDepthControlBest=(bestReadDepthRun*stdProp)^2;

           %Makes a 3d matrix to send to the power plotter
            plotPowers=[];
            plotReadDepths=[];

            for i=1:3
                fcForPlot=fcsPlot(i); 
                readDepthsSampled=getReadDepthsRun(probSequencedC, bestReadDepthRun, 50, nControlSamples+nTestSamples); %gets 50 sequencing depths at evenly spaced increments
                plotReadDepths(:,i)=readDepthsSampled;
                plotPowers(:,:,i)=getPowerByReadDepth( mVControl, vVControl, mVTest, vVTest, readDepthsSampled, bestNRepsRun, bestNRepsRun,  fcForPlot, pCut, 1);
            end

            [ powerPlot ] = getPowerPlot(plotPowers, probSequencedC.*bestReadDepthRun, plotReadDepths, fcsPlot, pCut, bestNRepsRun, bestReadDepthRun );

            filename1=strcat(outputDirectory,'powerPlotMostPowerful',outputTag,'.png');
            delete(filename1);
            print(powerPlot, '-dpng' , filename1 , '-r130');
        end
    catch
        
        warningString=strcat(warningString, '<br>ERROR! A fatal error has occured and Scotty cannot continue.  Please contact us so that we can troubleshoot this problem.');

    end

  
    %===================================================
    %Final Summary File
    %===================================================
    
    warningString 
    
    if length(warningString)<20
        warningString='';
    end
    
    resultString=warningString;
    
    %Add best experiment

    resultString=strcat(resultString, {'<br>Scotty has tested '}, num2str(experimentsEvaluated), {' possible experimental designs. '});  
   
    if isempty(cheapestExperiment)==0
       resultString=strcat(resultString, {'<br><br>The following experiments meet your criteria:'});  
       resultString=strcat(resultString, {'<blockquote>'});
       resultString=strcat(resultString, {'<br>Least expensive: '},num2str(cheapestExperiment(2)), {' replicates sequenced to a depth of '}, ...
           num2str(cheapestExperiment(1)/10^6) , {' million reads aligned to genes per replicate.'});
       resultString=strcat(resultString, {'<br>Most powerful: '},num2str(mostPowerfulExperiment(2)), {' replicates sequenced to a depth of '}, ...
           num2str(mostPowerfulExperiment(1)/10^6),  {' million reads aligned to genes per replicate.'});
    else
       resultString=strcat(resultString, {'<blockquote>'}); 
       resultString=strcat(resultString, {'<br>None of the experimental designs tested met your experimental criteria.'});
    end
     resultString=strcat(resultString, {'</blockquote>'});
    
    resultString=strcat(resultString, {'<br>The number of samples that is required is in part determined by how dispersed your biological replicates are.  '});
    resultString=strcat(resultString, {'We measured the dispersion of your replicates:'});  
    
    if nControlSamples>1
         resultString=strcat(resultString, {'<blockquote><br>Control samples replicate dispersion: '}, num2str(mVControl));
    end
    if nTestSamples>1
         resultString=strcat(resultString, {'<br>Test samples replicate dispersion: '}, num2str(mVTest));
    end
    
    resultString=strcat(resultString, {'</blockquote><br>The dispersion metric that Scotty uses is the mean overdispersion from Poisson.  Many factor can affect how dispersed replicates are.  '});
    resultString=strcat(resultString, {'For a general reference, most of the biological replicate pairs we examined had an overdipsersion between 0.2 and 0.4.'});    
       
    resultString=strcat(resultString, {'<br><br>We measured the number of unique genes observed in you data (detected by at least one read in one or the samples)  '});
    resultString=strcat(resultString, {'and estimated the number of genes that are expressed:'});  

    if nControlSamples>1
         resultString=strcat(resultString, {'<blockquote><br>Genes observed (Control): '}, num2str(observedGenesC ));
    end
    
    if nTestSamples>1
         resultString=strcat(resultString, {'<br>Genes observed (Test): '}, num2str(observedGenesT));
    end
    
    resultString=strcat(resultString, {'</blockquote>Power calculations (the % detected) are based on the number of observed genes.'});  
      
    resultString=resultString{1};           
    
    printResultFile( resultString, outputDirectory, outputTag );      
    
    readsRequiredControl=mean(readsRequired(1:nControlSamples));    
    errorReadsRequiredControl=std(readsRequired(1:nControlSamples));
    
    readsRequiredTest=mean(readsRequired(nControlSamples+1:nControlSamples+nTestSamples));    
    errorReadsRequiredTest=std(readsRequired(nControlSamples+1:nControlSamples+nTestSamples));    
  
    h=0;   
    
    
    %===================================================
    %Create Scatter Plots of Relevant Data - last because print might cause
    %segmentation fault if there are too many points.
    %===================================================
   
    genesToHighlight=[];
    colorsToHighlight=[];
    
    out='Making Control vs test Scatter Plot'
    
    if nControlSamples>=1 & nTestSamples>=1
        try
            xData=sum(data(:, 1:nControlSamples),2);  
            yData=sum(data(:, nControlSamples+1:size(data,2)),2);

            [ scatterPlot ] = scottyPlotScatter( xData, yData, genesToHighlight, colorsToHighlight );    
            filename1=strcat(outputDirectory,'scatterPlot',outputTag,'.png');
            delete(filename1);
            print(scatterPlot, '-dpng' , filename1 , '-r130');    
        catch
            warningString=strcat(warningString, '<br>Scotty was not able to run a scatter plot of your control vs test data.  Please contact us for more information.');

        end
    end
    
    out='Making Control Scatter Plot'

    %Make a scatter plot of the control replicates
    if nControlSamples>1
        try
            [ comparativeScatterControl ] = scottyPlotScatterComparingSamples(data(:,1:nControlSamples), sampleNames(1:nControlSamples) );
            filename1=strcat(outputDirectory,'scatterPlotControlReps',outputTag,'.png');
            delete(filename1);
            out='printing control plot'
            print(comparativeScatterControl , '-dpng' , filename1 , '-r130');   
        catch
             warningString=strcat(warningString, '<br>Scotty was not able to run a scatter plot of your control data.  Please contact us for more information.');
        end
    end
    
      
    out='Making Test Scatter Plot'

    %Make a scatter plot of the test replicates
    if nTestSamples>1 
        try
            [ comparativeScatterControl ] = scottyPlotScatterComparingSamples(data(:,nControlSamples+1:nControlSamples+nTestSamples), ...
                sampleNames(nControlSamples+1:nControlSamples+nTestSamples) );
            filename1=strcat(outputDirectory,'scatterPlotTestReps',outputTag,'.png');
            delete(filename1);
            print(comparativeScatterControl , '-dpng' , filename1 , '-r130'); 
        catch
             warningString=strcat(warningString, '<br>Scotty was not able to run a scatter plot of your test verus test data.  Please contact us for more information.');
        end
    end
   
    
    
    %===================================================
    %Clean up stuff and end
    %===================================================
    
    h=0;   
    
    if isdeployed()==1  
        close all;
    end
    
    
    
    try
        matlabpool close;
    catch
        
    end
    
    toc;
   
    
end

