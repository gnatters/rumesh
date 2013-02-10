
# Produces 4D transformation matrices.
# See http://www.j3d.org/matrix_faq/matrfaq_latest.html for an explanation of the Math.
# Decides on load to use the NMatrix class if the NArray gem is loaded, otherwise it falls back on the Matrix class (requiring it if neccessary).

module TransformationMatrix
  # This module variable determines on load whether to use NMatrix or Matrix depending on availability, with a preference for NMatrix.
  @@matrix_class = ( (defined? NMatrix) ? NMatrix : [ (require 'matrix'), Matrix ].last )
  
  # @param theta (Float) angle of rotation
  # @param axis (Array) of rotation, also accepts Symbols: `:x`, `:y`, or `:z`.
  # @return [NMatrix] describing the prescribed rotation transformation.
  def self.rotation theta, axis
    axis =  Hash[
      x: [1,0,0],
      y: [0,1,0],
      z: [0,0,1]
    ][axis] || axis
    
    if (Math.sqrt( axis[0]**2 + axis[1]**2 + axis[2]**2 )-1).abs > 0.0001
      l = Math.sqrt(axis[0]**2 + axis[1]**2 + axis[2]**2)
      axis = [axis[0]/l, axis[1]/l, axis[2]/l]
    end
    
    ct = Math.cos(theta)
    mct = 1-ct
    st = Math.sin(theta)
    @@matrix_class[[ ct + axis[0]**2*mct,              axis[0]*axis[1]*mct - axis[2]*st, axis[0]*axis[2]*mct + axis[1]*st, 0 ],
                   [ axis[1]*axis[0]*mct + axis[2]*st, ct + axis[1]**2*mct,              axis[1]*axis[2]*mct - axis[0]*st, 0 ],
                   [ axis[2]*axis[0]*mct - axis[1]*st, axis[2]*axis[1]*mct + axis[0]*st, ct + axis[2]**2*mct,              0 ],
                   [ 0,                                0,                                0,                                1 ]]
  end
  
  # @param *d accepts either single scaling factor, x, y and z scaling factors or an Array of x, y and z scaling vactors.
  # @return [NMatrix] describing the prescribed translation transformation, or the identity matrix if no arguments are given.
  def self.translation *d
    d = [*d].flatten
    @@matrix_class[[ 1, 0, 0, d[0] || 0 ],
  		             [ 0, 1, 0, d[1] || 0 ],
  		             [ 0, 0, 1, d[2] || 0 ],
  		             [ 0, 0, 0, 1         ]]
  end
  
  # @param *s accepts either single scaling factor, x, y and z scaling factors or an Array of x, y and z scaling vactors.
  # @return [NMatrix] describing the prescribed scaling transformation, or the identity matrix if no arguments are given.
  def self.scale *s
    s = [*s].flatten
    s[0] ||= 1
    s[1] ||= s[0]
    s[2] ||= s[0]
    @@matrix_class[[ s[0], 0,    0,    0 ],
  		             [ 0,    s[1], 0,    0 ],
  		             [ 0,    0,    s[2], 0 ],
  		             [ 0,    0,    0,    1 ]]
  end
end

# TransMat is an alias of the TransformationMatrix module.
TransMat = TransformationMatrix
