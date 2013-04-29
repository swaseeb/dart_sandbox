library gmm_log_lookup_typed;

import 'dart:math';
import 'dart:typed_data';

class DiagonalGaussian {

  Float32List means;
  Float32List variances;
  Float32List negativeHalfPrecisions;
  double C;

  DiagonalGaussian(this.means, this.variances) {
    // instead of using [-0.5 * 1/var[d]] during likelihood calculation we pre-compute the values.
    // This saves 1 mul 1 div operation.
    negativeHalfPrecisions = new Float32List(variances.length);
    for (int i = 0; i < negativeHalfPrecisions.length; i++) {
      negativeHalfPrecisions[i] = -0.5 / variances[i];
    } 
    // calculate the precomputed distance.
    // -0.5*SUM[d=1..D] ( log(2*PI) + log(var[d]) ) = -0.5*log(2*PI)*D -0.5 SUM[d=1..D](log(var[d]))
    double val = -0.5 * log(2 * PI) * variances.length;
    for (double variance in variances) {
      val -= (0.5 * log(variance));
    }
    C = val;      
  }

  double logLikelihood(Float32List data) {
    double res = 0.0;
    for (int i = 0; i < means.length; i++) {
        final double dif = data[i] - means[i];
        res += ((dif * dif) * negativeHalfPrecisions[i]);     
    }    
    return C + res;
  } 
}

class Gmm  {

  Float64List mixtureWeights;
  List<DiagonalGaussian> gaussians;

  Gmm(this.mixtureWeights, this.gaussians) {
    this.mixtureWeights = new Float64List.fromList(mixtureWeights);
    for(int i = 0; i< mixtureWeights.length; i++) {
      mixtureWeights[i] = log(mixtureWeights[i]);
    }
  }
  
  double score(Float32List data) {
    var result = mixtureWeights[0] + gaussians[0].logLikelihood(data);
    for (int i = 1; i < gaussians.length; ++i) {
      var b = mixtureWeights[i] + gaussians[i].logLikelihood(data);
      result = logMath.logSum(result, b);
    }
    return result;
  } 
}

LogMath logMath = new LogMath();

class LogMath {  
  const double _SCALE = 1000.0;
  
  static final LogMath _singleton = new LogMath._internal();
  
  final logSumLookup = new Float32List(20000);
  
  factory LogMath() {
    return _singleton;
  }
  
  LogMath._internal() {
    for (int i = 0; i < logSumLookup.length; i++) {
      logSumLookup[i] = log(1.0 + exp(-i / _SCALE));
    }
  }
  
  /**
   * Calculates an approximation of log(a+b) when log(a) and log(b) are given using the formula
   * log(a+b) = log(b) + log(1 + exp(log(a)-log(b))) where log(b)>log(a)
   * This method is an approximation because it uses a lookup table for log(1 + exp(log(b)-log(a))) part
   * This is useful for log-probabilities where values vary between -30 < log(p) <= 0
   * if difference between values is larger than 20 (which means sum of the numbers will be very close to the larger
   * value in linear domain) large value is returned instead of the logSum calculation because effect of the other
   * value is negligible
   */
  double logSum(double logA, double logB) {
    if (logA > logB) {
      double dif = logA - logB; // logA-logB because during lookup calculation dif is multiplied with -1
      return dif >= 20.0 ? logA : logA + logSumLookup[(dif * _SCALE).toInt()];
    } else {
      final double dif = logB - logA;
      return dif >= 20.0 ? logB : logB + logSumLookup[(dif * _SCALE).toInt()];
    }
  }  
}