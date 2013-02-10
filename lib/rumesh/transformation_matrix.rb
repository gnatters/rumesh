require 'narray'

class TransformationMatrix
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
    NMatrix[[ ct + axis[0]**2*mct,              axis[0]*axis[1]*mct - axis[2]*st, axis[0]*axis[2]*mct + axis[1]*st, 0 ],
            [ axis[1]*axis[0]*mct + axis[2]*st, ct + axis[1]**2*mct,              axis[1]*axis[2]*mct - axis[0]*st, 0 ],
            [ axis[2]*axis[0]*mct - axis[1]*st, axis[2]*axis[1]*mct + axis[0]*st, ct + axis[2]**2*mct,              0 ],
            [ 0,                                0,                                0,                                1 ]]
  end
  
  def self.translation *d
    d = [*d].flatten
  	NMatrix[[ 1, 0, 0, d[0] ],
  		      [ 0, 1, 0, d[1] ],
  		      [ 0, 0, 1, d[2] ],
  		      [ 0, 0, 0, 1    ]]
  end
  
  def self.scale *s
    s = [*s].flatten
    s[1] ||= s[0]
    s[2] ||= s[0]
  	NMatrix[[ s[0], 0,    0,    0 ],
  		      [ 0,    s[1], 0,    0 ],
  		      [ 0,    0,    s[2], 0 ],
  		      [ 0,    0,    0,    1 ]]
  end
end

class TransMat < TransformationMatrix
end