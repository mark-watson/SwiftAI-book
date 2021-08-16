# Using Apple's Core ML Machine Learning and Deep Learning Libraries

Please note that this chapter is specific to Apple's libraries and pre-trained deep learning models.

I assume that you are generally familiar with [Apple's CoreML documentation](https://developer.apple.com/documentation/coreml)

There are two example directories (from the github repository [https://github.com/mark-watson/SwiftAI-book-code](https://github.com/mark-watson/SwiftAI-book-code) for this chapter:

- SwiftAI-book-code/wisconsin_data_create_model generates a deep learning model
- SwiftAI-book-code/wisconsin_data_predict_with_model uses the trained model.

If you have taken a class in Deep Learning, you learned how to divide a training data set into separate training, dev, and test data sets. This process is handled internally by the CoreML libraries we use here so we will only be using a single training data file.

## Training a Classification Model For the University of Wisconsin Cancer Data

When building the example model (data in files **wisconsin.mlmodel***), a Swift file **wisconsin.swift** is auto-generated. In the project Makefile, notice that the make target **clean** removes these files:

{lang="makefile",linenos=on}
~~~~~~~~
build_model: clean
	swift build
	swift run

clean:
	rm -f Sources/wisconsin_data/wisconsin.mlmodel*
	rm -f Sources/wisconsin_data/wisconsin.swift
~~~~~~~~

The file **Sources/wisconsin_data/main.swift** reads a training file in CSV format and uses the CoreML libraries to train a prediction model. You might want to uncomment the print statement in line 10 to see the contents of the CSV formatted (i.e., a spreadsheet file) training data file. In lines 11-13 we define which columns in the input training CSV file that we will use to build our model (in this case we use all the data features).

{lang="swift",linenos=on}
~~~~~~~~
import Foundation
import CoreML
import CreateML

func create_model() {
    if #available(macOS 10.14, *) {
        let fileUrl = URL(fileURLWithPath: "labeled_cancer_data.csv")
        print(fileUrl)
        if let dataTable = try? MLDataTable(contentsOf: fileUrl) {
            //print(dataTable)
            let regressorColumns = ["Cl.thickness", "Cell.size",
                                    "Cell.shape", "Marg.adhesion",
                                    "Epith.c.size", "Bare.nuclei",
                                    "Bl.cromatin", "Normal.nucleoli",
                                    "Mitoses", "Class"]
            
            // Classifier:
            let classifierTable = dataTable[regressorColumns]
            let (classifierEvaluationTable, classifierTrainingTable) =
              classifierTable.randomSplit(by: 0.20, seed: 5)
            let classifier = try! MLClassifier(trainingData: classifierTrainingTable,
                                              targetColumn: "Class")
            print("++ classifier.description:", classifier)
            /// Classifier training accuracy as a percentage
            let trainingError = classifier.trainingMetrics.classificationError
            let trainingAccuracy = (1.0 - trainingError) * 100
            print("trainingAccuracy:", trainingAccuracy)
            
            /// Classifier validation accuracy as a percentage
            let validationError = classifier.validationMetrics.classificationError
            print("validationError:", validationError)
            let validationAccuracy = (1.0 - validationError) * 100
            print("validationAccuracy:", validationAccuracy)
            /// Evaluate the classifier
            let classifierEvaluation =
              classifier.evaluation(on: classifierEvaluationTable)
            
            /// Classifier evaluation accuracy as a percentage
            let evaluationError = classifierEvaluation.classificationError
            print("evaluationError:", evaluationError)
            let evaluationAccuracy = (1.0 - evaluationError) * 100
            print("evaluationAccuracy:", evaluationAccuracy)
            
            let classifierMetadata =
              MLModelMetadata(author: "Mark Watson",
                              shortDescription: "Wisconsin Cancer Dataset",
                              version: "1.0")
            
            /// Save the trained classifier model to the Desktop.
            let _ =
              try? classifier.write(to: URL(fileURLWithPath:
                                           "Sources/wisconsin_data/wisconsin.mlmodel"),
                                           metadata: classifierMetadata)
        }
    }
}

create_model()
~~~~~~~~

{lang="bash",linenos=on}
~~~~~~~~
$ make
rm -f Sources/wisconsin_data/wisconsin.mlmodel*
rm -f Sources/wisconsin_data/wisconsin.swift
swift build
[0/0] Build complete!
swift run
[0/0] Build complete!
column_type_hints = {}
Finished parsing file /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_create_model/labeled_cancer_data.csv
Parsing completed. Parsed 100 lines in 0.01006 secs.
Finished parsing file /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_create_model/labeled_cancer_data.csv
Parsing completed. Parsed 683 lines in 0.003458 secs.
Using 9 features to train a model to predict Class.

Automatically generating validation set from 5% of the data.
Boosted trees classifier:
--------------------------------------------------------
Number of examples          : 522
Number of classes           : 2
Number of feature columns   : 9
Number of unpacked features : 9
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
| Iteration | Elapsed Time | Training Accuracy | Validation Accuracy | Training Log Loss | Validation Log Loss |
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
| 1         | 0.006108     | 0.988506          | 0.904762            | 0.459892          | 0.520190            |
| 2         | 0.010718     | 0.984674          | 0.857143            | 0.329561          | 0.412062            |
| 3         | 0.015658     | 0.984674          | 0.857143            | 0.245602          | 0.337748            |
| 4         | 0.020130     | 0.986590          | 0.857143            | 0.186529          | 0.291379            |
| 5         | 0.024706     | 0.990421          | 0.857143            | 0.144306          | 0.262312            |
| 10        | 0.043619     | 0.996169          | 0.904762            | 0.049835          | 0.180445            |
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
Random forest classifier:
--------------------------------------------------------
Number of examples          : 522
Number of classes           : 2
Number of feature columns   : 9
Number of unpacked features : 9
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
| Iteration | Elapsed Time | Training Accuracy | Validation Accuracy | Training Log Loss | Validation Log Loss |
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
| 1         | 0.002102     | 0.984674          | 0.904762            | 0.173523          | 0.305533            |
| 2         | 0.003890     | 0.986590          | 0.904762            | 0.171982          | 0.306030            |
| 3         | 0.005461     | 0.984674          | 0.904762            | 0.173111          | 0.276622            |
| 4         | 0.006758     | 0.984674          | 0.904762            | 0.171693          | 0.285118            |
| 5         | 0.007481     | 0.982759          | 0.952381            | 0.172563          | 0.273630            |
| 10        | 0.011962     | 0.984674          | 0.952381            | 0.171195          | 0.261603            |
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
Decision tree classifier:
--------------------------------------------------------
Number of examples          : 522
Number of classes           : 2
Number of feature columns   : 9
Number of unpacked features : 9
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
| Iteration | Elapsed Time | Training Accuracy | Validation Accuracy | Training Log Loss | Validation Log Loss |
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
| 1         | 0.002216     | 0.988506          | 0.904762            | 0.170105          | 0.352356            |
+-----------+--------------+-------------------+---------------------+-------------------+---------------------+
SVM:
--------------------------------------------------------
Number of examples          : 522
Number of classes           : 2
Number of feature columns   : 9
Number of unpacked features : 9
Number of coefficients    : 10
Starting L-BFGS 
--------------------------------------------------------
+-----------+----------+-----------+--------------+-------------------+---------------------+
| Iteration | Passes   | Step size | Elapsed Time | Training Accuracy | Validation Accuracy |
+-----------+----------+-----------+--------------+-------------------+---------------------+
| 0         | 2        | 1.000000  | 0.000629     | 0.350575          | 0.285714            |
| 1         | 6        | 3.000000  | 0.001610     | 0.908046          | 0.857143            |
| 2         | 7        | 3.000000  | 0.002089     | 0.840996          | 0.809524            |
| 3         | 12       | 1.053671  | 0.004093     | 0.961686          | 0.952381            |
| 4         | 13       | 1.053671  | 0.004610     | 0.959770          | 0.904762            |
| 9         | 20       | 1.053671  | 0.007046     | 0.971264          | 0.904762            |
+-----------+----------+-----------+--------------+-------------------+---------------------+
Logistic regression:
--------------------------------------------------------
Number of examples          : 522
Number of classes           : 2
Number of feature columns   : 9
Number of unpacked features : 9
Number of coefficients      : 10
Starting Newton Method 
--------------------------------------------------------
+-----------+----------+--------------+-------------------+---------------------+
| Iteration | Passes   | Elapsed Time | Training Accuracy | Validation Accuracy |
+-----------+----------+--------------+-------------------+---------------------+
| 1         | 2        | 0.000373     | 0.967433          | 0.904762            |
| 2         | 3        | 0.000724     | 0.969349          | 0.904762            |
| 3         | 4        | 0.001080     | 0.975096          | 0.904762            |
| 4         | 5        | 0.001427     | 0.978927          | 0.904762            |
| 5         | 6        | 0.001796     | 0.978927          | 0.904762            |
| 7         | 8        | 0.002388     | 0.978927          | 0.904762            |
+-----------+----------+--------------+-------------------+---------------------+
SUCCESS: Optimal solution found.

++ classifier.description: RandomForestClassifier

Parameters
Max Depth: 6
Max Iterations: 10
Min Loss Reduction: 0.0
Min Child Weight: 0.0
Random Seed: 42
Row Subsample: 0.8
Column Subsample: 0.8

Performance on Training Data
Number of examples: 522
Number of classes: 2
Accuracy: 98.47%

Performance on Validation Data
Number of examples: 21
Number of classes: 2
Accuracy: 95.24%

trainingAccuracy: 98.46743295019157
validationError: 0.04761904761904767
validationAccuracy: 95.23809523809523
evaluationError: 0.050000000000000044
evaluationAccuracy: 95.0
Trained model successfully saved at /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_create_model/Sources/wisconsin_data/wisconsin.mlmodel.
~~~~~~~~



## Using the Classification Model For the University of Wisconsin Cancer Data



{lang="makefile",linenos=on}
~~~~~~~~
build_preditor: clean
	cp ../wisconsin_data_create_model/Sources/wisconsin_data/wisconsin.mlmodel Sources/wisconsin_data/
	cd Sources/wisconsin_data; xcrun coremlcompiler generate wisconsin.mlmodel --language Swift .
	cd Sources/wisconsin_data; xcrun coremlcompiler compile wisconsin.mlmodel .
	swift build
	swift run

clean:
	rm -rf Sources/wisconsin_data/wisconsin.mlmodel*
	rm -rf Sources/wisconsin_data/wisconsin.swift
~~~~~~~~


{lang="swift",linenos=on}
~~~~~~~~
import Foundation
import CoreML
import CreateML

func predict() {
    if #available(macOS 10.14, *) {
        
        //let url = wisconsin_data_create_model.url(forResource: "wisconsin", withExtension: "mlmodelc")!
        let modelUrl = URL(fileURLWithPath: "Sources/wisconsin_data/wisconsin.mlmodelc")
        let pretrained_model = try! wisconsin(contentsOf: modelUrl, configuration: MLModelConfiguration())
        
        //let pretrained_model = try? wisconsin(configuration: MLModelConfiguration()) {
        let sampleInput = wisconsinInput(Cl_thickness: 3, Cell_size: 2, Cell_shape: 5, Marg_adhesion: 8, Epith_c_size: 8, Bare_nuclei: 2, Bl_cromatin: 3, Normal_nucleoli: 7, Mitoses: 4)
        let a_prediction = try! pretrained_model.prediction(input: sampleInput)
        print(a_prediction.featureNames)
        print("Class:", a_prediction.featureValue(for: "Class")!)
        print("ClassProbability:", a_prediction.featureValue(for: "ClassProbability")!)

    }
}

predict()
~~~~~~~~


{lang="bash",linenos=on}
~~~~~~~~
$ make
rm -rf Sources/wisconsin_data/wisconsin.mlmodel*
rm -rf Sources/wisconsin_data/wisconsin.swift
cp ../wisconsin_data_create_model/Sources/wisconsin_data/wisconsin.mlmodel Sources/wisconsin_data/
cd Sources/wisconsin_data; xcrun coremlcompiler generate wisconsin.mlmodel --language Swift .
/Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.swift
cd Sources/wisconsin_data; xcrun coremlcompiler compile wisconsin.mlmodel .
/Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodelc/coremldata.bin
/Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodelc/analytics/coremldata.bin
/Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodelc/model0/coremldata.bin
/Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodelc/model1/coremldata.bin
/Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodelc/model1/_B0000.DAT
swift build
'wisconsin_data' /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model: warning: found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodel

[4/4] Build complete!
swift run
'wisconsin_data' /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model: warning: found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /Users/markw_1/GITHUB/SwiftAI-book-code/wisconsin_data_predict_with_model/Sources/wisconsin_data/wisconsin.mlmodel

[0/0] Build complete!
["Class", "ClassProbability"]
Class: Int : 0
ClassProbability: Dictionary : {
    0 = "0.7969631955468645";
    1 = "0.2030368044531356";
}
~~~~~~~~


